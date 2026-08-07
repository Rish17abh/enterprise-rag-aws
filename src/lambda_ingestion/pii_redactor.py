"""
Phase 2 — PII redaction & chunking Lambda.

Triggered via Step Functions when a PDF/TXT object is uploaded to the
ingestion bucket. Uses Amazon Comprehend for PII detection, writes
sanitized overlapping chunks to s3://{bucket}/processed/.
"""

from __future__ import annotations

import io
import json
import logging
import os
import re
import urllib.parse
from datetime import datetime, timezone
from typing import Any

import boto3
from botocore.exceptions import BotoCoreError, ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Approximate tokens as whitespace-separated words for chunking
CHUNK_SIZE_TOKENS = int(os.environ.get("CHUNK_SIZE_TOKENS", "500"))
CHUNK_OVERLAP_TOKENS = int(os.environ.get("CHUNK_OVERLAP_TOKENS", "50"))
PROCESSED_PREFIX = os.environ.get("PROCESSED_PREFIX", "processed/")
# Guide-required types; CREDIT_DEBIT_NUMBER is Comprehend's card number type
PII_TYPES = {"SSN", "EMAIL", "NAME", "PHONE", "CREDIT_DEBIT_NUMBER"}
PII_LABELS = {
    "SSN": "SSN",
    "EMAIL": "EMAIL",
    "NAME": "NAME",
    "PHONE": "PHONE",
    "CREDIT_DEBIT_NUMBER": "CREDIT_CARD",
}

s3 = boto3.client("s3")
comprehend = boto3.client("comprehend")


def handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """
    Expected Step Functions input (normalized):
      {
        "bucket": "...",
        "key": "uploads/file.pdf",
        "source_event": {...}  # optional
      }
    """
    logger.info("Received event: %s", json.dumps(event, default=str))

    try:
        bucket, key = _extract_s3_location(event)
        if not key.lower().endswith((".pdf", ".txt")):
            raise ValueError(f"Unsupported object key extension: {key}")

        # Skip already-processed objects to avoid recursion
        if key.startswith(PROCESSED_PREFIX):
            logger.info("Skipping processed/ object: %s", key)
            return {
                "status": "SKIPPED",
                "reason": "object_under_processed_prefix",
                "bucket": bucket,
                "key": key,
            }

        raw_bytes = _download_object(bucket, key)
        text = _extract_text(key, raw_bytes)
        if not text.strip():
            raise ValueError("Extracted text is empty")

        redacted_text, pii_counts = _redact_pii(text)
        chunks = _chunk_text(redacted_text, CHUNK_SIZE_TOKENS, CHUNK_OVERLAP_TOKENS)

        output_key = _processed_key(key)
        payload = {
            "source_document": key,
            "source_bucket": bucket,
            "processed_at": datetime.now(timezone.utc).isoformat(),
            "pii_masked_flag": bool(pii_counts),
            "pii_entity_counts": pii_counts,
            "chunk_count": len(chunks),
            "chunk_size_tokens": CHUNK_SIZE_TOKENS,
            "chunk_overlap_tokens": CHUNK_OVERLAP_TOKENS,
            "chunks": chunks,
        }
        _write_json(bucket, output_key, payload)

        result = {
            "status": "SUCCESS",
            "bucket": bucket,
            "source_key": key,
            "processed_key": output_key,
            "chunk_count": len(chunks),
            "pii_masked_flag": bool(pii_counts),
            "pii_entity_counts": pii_counts,
        }
        logger.info("PII redaction complete: %s", json.dumps(result))
        return result

    except (ClientError, BotoCoreError, ValueError, OSError) as exc:
        logger.exception("PII redaction failed: %s", exc)
        return {
            "status": "FAILED",
            "error_type": type(exc).__name__,
            "error_message": str(exc),
            "event": event,
        }


def _extract_s3_location(event: dict[str, Any]) -> tuple[str, str]:
    """Normalize S3 bucket/key from Step Functions or EventBridge shapes."""
    if event.get("bucket") and event.get("key"):
        return event["bucket"], urllib.parse.unquote_plus(event["key"])

    # EventBridge S3 Object Created (detail)
    detail = event.get("detail") or {}
    if detail.get("bucket") and detail.get("object"):
        bucket = detail["bucket"].get("name") or detail["bucket"].get("bucketName")
        key = detail["object"].get("key")
        if bucket and key:
            return bucket, urllib.parse.unquote_plus(key)

    # Nested from EventBridge -> Step Functions input path
    if "Records" in event:
        record = event["Records"][0]
        bucket = record["s3"]["bucket"]["name"]
        key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])
        return bucket, key

    raise ValueError("Unable to resolve S3 bucket/key from event")


def _download_object(bucket: str, key: str) -> bytes:
    try:
        response = s3.get_object(Bucket=bucket, Key=key)
        return response["Body"].read()
    except ClientError as exc:
        logger.error("Failed to download s3://%s/%s: %s", bucket, key, exc)
        raise


def _extract_text(key: str, raw_bytes: bytes) -> str:
    lower = key.lower()
    if lower.endswith(".txt"):
        return raw_bytes.decode("utf-8", errors="replace")

    if lower.endswith(".pdf"):
        try:
            from pypdf import PdfReader
        except ImportError as exc:
            raise RuntimeError("pypdf is required for PDF extraction") from exc

        reader = PdfReader(io.BytesIO(raw_bytes))
        pages: list[str] = []
        for page in reader.pages:
            try:
                pages.append(page.extract_text() or "")
            except Exception as exc:  # noqa: BLE001 - continue other pages
                logger.warning("Failed to extract a PDF page: %s", exc)
        return "\n".join(pages)

    raise ValueError(f"Unsupported file type for key={key}")


def _redact_pii(text: str) -> tuple[str, dict[str, int]]:
    """
    Detect PII with Comprehend and replace matches with [REDACTED_<TYPE>].
    Comprehend DetectPiiEntities accepts up to 100 KB per call.
    """
    max_bytes = 90_000  # stay under 100KB UTF-8 limit with margin
    segments = _split_by_byte_size(text, max_bytes)
    redacted_segments: list[str] = []
    counts: dict[str, int] = {}

    for segment in segments:
        try:
            response = comprehend.detect_pii_entities(Text=segment, LanguageCode="en")
        except ClientError as exc:
            logger.error("Comprehend detect_pii_entities failed: %s", exc)
            raise

        entities = [e for e in response.get("Entities", []) if e.get("Type") in PII_TYPES]
        entities.sort(key=lambda e: e["BeginOffset"], reverse=True)

        redacted = segment
        for entity in entities:
            pii_type = entity["Type"]
            label = PII_LABELS[pii_type]
            start = entity["BeginOffset"]
            end = entity["EndOffset"]
            redacted = f"{redacted[:start]}[REDACTED_{label}]{redacted[end:]}"
            counts[label] = counts.get(label, 0) + 1

        redacted_segments.append(redacted)

    return "".join(redacted_segments), counts


def _split_by_byte_size(text: str, max_bytes: int) -> list[str]:
    encoded = text.encode("utf-8")
    if len(encoded) <= max_bytes:
        return [text]

    segments: list[str] = []
    start = 0
    while start < len(encoded):
        end = min(start + max_bytes, len(encoded))
        # avoid splitting mid-codepoint
        while end > start and (encoded[end - 1] & 0xC0) == 0x80:
            end -= 1
        piece = encoded[start:end].decode("utf-8", errors="ignore")
        segments.append(piece)
        start = end
    return segments


def _chunk_text(text: str, chunk_size: int, overlap: int) -> list[dict[str, Any]]:
    tokens = re.findall(r"\S+", text)
    if not tokens:
        return []

    if overlap >= chunk_size:
        raise ValueError("CHUNK_OVERLAP_TOKENS must be smaller than CHUNK_SIZE_TOKENS")

    chunks: list[dict[str, Any]] = []
    start = 0
    index = 0
    while start < len(tokens):
        end = min(start + chunk_size, len(tokens))
        chunk_tokens = tokens[start:end]
        chunks.append(
            {
                "chunk_id": index,
                "text_chunk": " ".join(chunk_tokens),
                "token_count": len(chunk_tokens),
                "start_token": start,
                "end_token": end,
            }
        )
        index += 1
        if end == len(tokens):
            break
        start = end - overlap

    return chunks


def _processed_key(source_key: str) -> str:
    safe_name = source_key.replace("/", "_")
    if safe_name.lower().endswith((".pdf", ".txt")):
        safe_name = safe_name.rsplit(".", 1)[0]
    return f"{PROCESSED_PREFIX}{safe_name}/chunks.json"


def _write_json(bucket: str, key: str, payload: dict[str, Any]) -> None:
    body = json.dumps(payload, ensure_ascii=False, indent=2).encode("utf-8")
    try:
        s3.put_object(
            Bucket=bucket,
            Key=key,
            Body=body,
            ContentType="application/json",
            ServerSideEncryption="aws:kms",
            SSEKMSKeyId=os.environ["KMS_KEY_ARN"],
        )
    except ClientError as exc:
        logger.error("Failed to write s3://%s/%s: %s", bucket, key, exc)
        raise
