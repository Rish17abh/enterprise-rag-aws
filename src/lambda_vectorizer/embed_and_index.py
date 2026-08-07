"""
Phase 3 — Bedrock Titan embeddings + OpenSearch Serverless indexing.

Reads Phase 2 processed chunks from S3, embeds each chunk with
amazon.titan-embed-text-v2:0, and indexes vectors into AOSS.
"""

from __future__ import annotations

import json
import logging
import os
import time
from datetime import datetime, timezone
from typing import Any
from urllib.parse import urlparse

import boto3
from botocore.exceptions import BotoCoreError, ClientError
from opensearchpy import AWSV4SignerAuth, OpenSearch, RequestsHttpConnection
from opensearchpy.exceptions import RequestError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Titan Text Embeddings V2 supports 1024 / 512 / 256 (not 1536 — that is V1).
EMBED_MODEL_ID = os.environ.get("EMBED_MODEL_ID", "amazon.titan-embed-text-v2:0")
EMBED_DIMENSIONS = int(os.environ.get("EMBED_DIMENSIONS", "1024"))
OPENSEARCH_ENDPOINT = os.environ["OPENSEARCH_ENDPOINT"]
OPENSEARCH_INDEX = os.environ.get("OPENSEARCH_INDEX", "rag-chunks")
AWS_REGION = os.environ.get("AWS_REGION") or os.environ.get("AWS_DEFAULT_REGION", "us-east-1")
KMS_KEY_ARN = os.environ["KMS_KEY_ARN"]

s3 = boto3.client("s3")
bedrock = boto3.client("bedrock-runtime", region_name=AWS_REGION)
_opensearch_client: OpenSearch | None = None


def handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """
    Expected input (Phase 2 SUCCESS payload):
      {
        "status": "SUCCESS",
        "bucket": "...",
        "processed_key": "processed/.../chunks.json",
        "source_key": "...",
        "pii_masked_flag": true
      }
    """
    logger.info("Received event: %s", json.dumps(event, default=str))

    try:
        if event.get("status") != "SUCCESS":
            raise ValueError(f"Expected Phase 2 SUCCESS payload, got status={event.get('status')}")

        bucket = event["bucket"]
        processed_key = event["processed_key"]
        source_key = event.get("source_key") or event.get("source_document") or processed_key

        payload = _load_chunks(bucket, processed_key)
        chunks = payload.get("chunks") or []
        if not chunks:
            raise ValueError("No chunks found in processed payload")

        pii_masked_flag = bool(payload.get("pii_masked_flag", event.get("pii_masked_flag", False)))
        client = _get_opensearch()
        _ensure_index(client)

        indexed = 0
        failed = 0
        for chunk in chunks:
            text = chunk.get("text_chunk") or ""
            if not text.strip():
                continue
            try:
                vector = _embed_text(text)
                doc = {
                    "vector": vector,
                    "text_chunk": text,
                    "source_document": payload.get("source_document") or source_key,
                    "timestamp": datetime.now(timezone.utc).isoformat(),
                    "pii_masked_flag": pii_masked_flag,
                    "chunk_id": chunk.get("chunk_id"),
                    "processed_key": processed_key,
                }
                # OpenSearch Serverless does not allow client-specified document IDs on index
                client.index(index=OPENSEARCH_INDEX, body=doc)
                indexed += 1
            except (ClientError, BotoCoreError, RequestError, ValueError) as exc:
                failed += 1
                logger.exception("Failed to embed/index chunk_id=%s: %s", chunk.get("chunk_id"), exc)

        if indexed == 0:
            raise RuntimeError(f"No chunks indexed (failed={failed})")

        result = {
            "status": "SUCCESS",
            "bucket": bucket,
            "processed_key": processed_key,
            "source_document": payload.get("source_document") or source_key,
            "index_name": OPENSEARCH_INDEX,
            "indexed_count": indexed,
            "failed_count": failed,
            "embed_model_id": EMBED_MODEL_ID,
            "embed_dimensions": EMBED_DIMENSIONS,
            "pii_masked_flag": pii_masked_flag,
        }
        logger.info("Indexing complete: %s", json.dumps(result))
        return result

    except (ClientError, BotoCoreError, ValueError, RuntimeError, OSError) as exc:
        logger.exception("Vector indexing failed: %s", exc)
        return {
            "status": "FAILED",
            "error_type": type(exc).__name__,
            "error_message": str(exc),
            "event": event,
        }


def _load_chunks(bucket: str, key: str) -> dict[str, Any]:
    try:
        response = s3.get_object(Bucket=bucket, Key=key)
        return json.loads(response["Body"].read().decode("utf-8"))
    except ClientError as exc:
        logger.error("Failed to read s3://%s/%s: %s", bucket, key, exc)
        raise


def _embed_text(text: str) -> list[float]:
    body = {
        "inputText": text,
        "dimensions": EMBED_DIMENSIONS,
        "normalize": True,
    }
    try:
        response = bedrock.invoke_model(
            modelId=EMBED_MODEL_ID,
            contentType="application/json",
            accept="application/json",
            body=json.dumps(body).encode("utf-8"),
        )
        payload = json.loads(response["body"].read())
        embedding = payload.get("embedding")
        if not embedding or len(embedding) != EMBED_DIMENSIONS:
            raise ValueError(
                f"Unexpected embedding size={len(embedding) if embedding else None}, expected={EMBED_DIMENSIONS}"
            )
        return embedding
    except ClientError as exc:
        logger.error("Bedrock InvokeModel failed: %s", exc)
        raise


def _get_opensearch() -> OpenSearch:
    global _opensearch_client
    if _opensearch_client is not None:
        return _opensearch_client

    host = OPENSEARCH_ENDPOINT.replace("https://", "").replace("http://", "").rstrip("/")
    credentials = boto3.Session().get_credentials()
    auth = AWSV4SignerAuth(credentials, AWS_REGION, "aoss")
    _opensearch_client = OpenSearch(
        hosts=[{"host": host, "port": 443}],
        http_auth=auth,
        use_ssl=True,
        verify_certs=True,
        connection_class=RequestsHttpConnection,
        timeout=60,
    )
    return _opensearch_client


def _ensure_index(client: OpenSearch) -> None:
    try:
        exists = client.indices.exists(index=OPENSEARCH_INDEX)
    except Exception:  # noqa: BLE001
        exists = False

    if exists:
        return

    body = {
        "settings": {
            "index": {
                "knn": True,
                "knn.algo_param.ef_search": 100,
            }
        },
        "mappings": {
            "properties": {
                "vector": {
                    "type": "knn_vector",
                    "dimension": EMBED_DIMENSIONS,
                    "method": {
                        "name": "hnsw",
                        "engine": "faiss",
                        "space_type": "cosinesimil",
                        "parameters": {
                            "ef_construction": 128,
                            "m": 16,
                        },
                    },
                },
                "text_chunk": {"type": "text"},
                "source_document": {"type": "keyword"},
                "timestamp": {"type": "date"},
                "pii_masked_flag": {"type": "boolean"},
                "chunk_id": {"type": "integer"},
                "processed_key": {"type": "keyword"},
            }
        },
    }

    try:
        client.indices.create(index=OPENSEARCH_INDEX, body=body)
        logger.info("Created OpenSearch index %s", OPENSEARCH_INDEX)
        # AOSS index creation can lag briefly before accepts docs
        time.sleep(2)
    except RequestError as exc:
        # Race: another concurrent invoke created it
        if "resource_already_exists_exception" not in str(exc).lower():
            raise
        logger.info("Index %s already exists", OPENSEARCH_INDEX)
