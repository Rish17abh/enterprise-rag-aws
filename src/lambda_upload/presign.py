"""
Presign S3 PUT URLs for browser document uploads (.pdf / .txt).

Returns a short-lived URL plus required SSE-KMS headers so the browser
can upload directly to the private ingestion bucket.
"""

from __future__ import annotations

import json
import logging
import os
import re
import uuid
from datetime import datetime, timezone
from typing import Any

import boto3
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# SSE-KMS PutObject requires SigV4; default SigV2 URLs are rejected by S3.
s3 = boto3.client(
    "s3",
    config=Config(signature_version="s3v4", s3={"addressing_style": "virtual"}),
)

BUCKET = os.environ["UPLOAD_BUCKET"]
KMS_KEY_ARN = os.environ["KMS_KEY_ARN"]
URL_EXPIRES_SECONDS = int(os.environ.get("URL_EXPIRES_SECONDS", "300"))
ALLOWED_EXTENSIONS = {".pdf", ".txt"}

CORS_HEADERS = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type,X-Api-Key,Authorization",
    "Access-Control-Allow-Methods": "OPTIONS,POST,GET",
}


def handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    method = (
        event.get("httpMethod")
        or event.get("requestContext", {}).get("http", {}).get("method")
        or "POST"
    )
    if method == "OPTIONS":
        return _response(200, {"ok": True})

    try:
        body = _parse_body(event)
        filename = str(body.get("filename") or "").strip()
        content_type = str(body.get("content_type") or body.get("contentType") or "").strip()

        if not filename:
            return _response(400, {"error": "filename is required"})

        safe_name, extension = _sanitize_filename(filename)
        if extension not in ALLOWED_EXTENSIONS:
            return _response(400, {"error": "Only .pdf and .txt files are supported"})

        if not content_type:
            content_type = "application/pdf" if extension == ".pdf" else "text/plain"

        object_key = _object_key(safe_name)
        params = {
            "Bucket": BUCKET,
            "Key": object_key,
            "ContentType": content_type,
            "ServerSideEncryption": "aws:kms",
            "SSEKMSKeyId": KMS_KEY_ARN,
        }
        upload_url = s3.generate_presigned_url(
            ClientMethod="put_object",
            Params=params,
            ExpiresIn=URL_EXPIRES_SECONDS,
            HttpMethod="PUT",
        )

        payload = {
            "upload_url": upload_url,
            "bucket": BUCKET,
            "key": object_key,
            "expires_in": URL_EXPIRES_SECONDS,
            "required_headers": {
                "Content-Type": content_type,
                "x-amz-server-side-encryption": "aws:kms",
                "x-amz-server-side-encryption-aws-kms-key-id": KMS_KEY_ARN,
            },
            "next_steps": [
                "PUT the file bytes to upload_url with required_headers",
                "S3 event starts Step Functions ingestion automatically",
                "Ask questions via POST /query after indexing completes",
            ],
        }
        logger.info("Presigned upload for key=%s", object_key)
        return _response(200, payload)

    except (ClientError, BotoCoreError, ValueError, OSError) as exc:
        logger.exception("Presign failed: %s", exc)
        return _response(
            500,
            {
                "error": "Failed to create upload URL",
                "error_type": type(exc).__name__,
                "error_message": str(exc),
            },
        )


def _parse_body(event: dict[str, Any]) -> dict[str, Any]:
    body = event.get("body", {})
    if isinstance(body, str):
        if event.get("isBase64Encoded"):
            import base64

            body = base64.b64decode(body).decode("utf-8")
        body = json.loads(body) if body else {}
    if not isinstance(body, dict):
        raise ValueError("Request body must be a JSON object")
    return body


def _sanitize_filename(filename: str) -> tuple[str, str]:
    base = filename.split("/")[-1].split("\\")[-1]
    match = re.search(r"(\.[A-Za-z0-9]+)$", base)
    extension = match.group(1).lower() if match else ""
    stem = base[: -len(extension)] if extension else base
    stem = re.sub(r"[^A-Za-z0-9._-]+", "_", stem).strip("._") or "document"
    stem = stem[:80]
    return f"{stem}{extension}", extension


def _object_key(safe_name: str) -> str:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    return f"uploads/{stamp}-{uuid.uuid4().hex[:8]}-{safe_name}"


def _response(status_code: int, body: dict[str, Any]) -> dict[str, Any]:
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Cache-Control": "no-store",
            **CORS_HEADERS,
        },
        "body": json.dumps(body),
    }
