"""
Phase 4 — Secure RAG query Lambda.

Embeds the user question with Titan, retrieves top-k chunks from
OpenSearch Serverless, and answers with Claude 3 Haiku using a
strict context-only system prompt.
"""

from __future__ import annotations

import json
import logging
import os
import time
from typing import Any

import boto3
from botocore.exceptions import BotoCoreError, ClientError
from opensearchpy import AWSV4SignerAuth, OpenSearch, RequestsHttpConnection

logger = logging.getLogger()
logger.setLevel(logging.INFO)

EMBED_MODEL_ID = os.environ.get("EMBED_MODEL_ID", "amazon.titan-embed-text-v2:0")
EMBED_DIMENSIONS = int(os.environ.get("EMBED_DIMENSIONS", "1024"))
LLM_MODEL_ID = os.environ.get("LLM_MODEL_ID", "us.anthropic.claude-haiku-4-5-20251001-v1:0")
OPENSEARCH_ENDPOINT = os.environ["OPENSEARCH_ENDPOINT"]
OPENSEARCH_INDEX = os.environ.get("OPENSEARCH_INDEX", "rag-chunks")
AWS_REGION = os.environ.get("AWS_REGION") or os.environ.get("AWS_DEFAULT_REGION", "us-east-1")
TOP_K = int(os.environ.get("TOP_K", "3"))
MAX_TOKENS = int(os.environ.get("MAX_TOKENS", "1024"))

SYSTEM_PROMPT_TEMPLATE = (
    "You are a secure corporate assistant. Answer the question ONLY based on the "
    "context provided below. If the answer cannot be found, reply "
    "'I do not have access to that information.'\n"
    "CONTEXT:\n{retrieved_chunks}"
)

bedrock = boto3.client("bedrock-runtime", region_name=AWS_REGION)
_opensearch_client: OpenSearch | None = None


def handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    logger.info("Received event: %s", json.dumps(_redact_event(event), default=str))

    try:
        question = _extract_question(event)
        if not question:
            return _response(400, {"error": "Missing required field: question"})

        t0 = time.perf_counter()
        query_vector = _embed_text(question)
        embed_ms = (time.perf_counter() - t0) * 1000.0

        t1 = time.perf_counter()
        hits = _knn_search(query_vector, k=TOP_K)
        retrieval_ms = (time.perf_counter() - t1) * 1000.0

        context_text, sources = _format_context(hits)
        system_prompt = SYSTEM_PROMPT_TEMPLATE.format(retrieved_chunks=context_text)

        t2 = time.perf_counter()
        answer, usage = _invoke_claude(system_prompt, question)
        llm_ms = (time.perf_counter() - t2) * 1000.0
        total_ms = (time.perf_counter() - t0) * 1000.0

        return _response(
            200,
            {
                "answer": answer,
                "sources": sources,
                "retrieved_count": len(hits),
                "model_id": LLM_MODEL_ID,
                "embed_model_id": EMBED_MODEL_ID,
                "usage": usage,
                "latency_ms": {
                    "embedding": round(embed_ms, 2),
                    "retrieval": round(retrieval_ms, 2),
                    "llm": round(llm_ms, 2),
                    "total": round(total_ms, 2),
                },
            },
        )

    except (ClientError, BotoCoreError, ValueError, RuntimeError, OSError) as exc:
        logger.exception("RAG query failed: %s", exc)
        return _response(
            500,
            {
                "error": "RAG query failed",
                "error_type": type(exc).__name__,
                "error_message": str(exc),
            },
        )


def _extract_question(event: dict[str, Any]) -> str:
    # API Gateway Lambda proxy: body is a JSON string
    body = event.get("body", event)
    if isinstance(body, str):
        if event.get("isBase64Encoded"):
            import base64

            body = base64.b64decode(body).decode("utf-8")
        body = json.loads(body) if body else {}
    if not isinstance(body, dict):
        raise ValueError("Request body must be a JSON object")
    question = body.get("question")
    if question is None:
        return ""
    return str(question).strip()


def _embed_text(text: str) -> list[float]:
    body = {
        "inputText": text,
        "dimensions": EMBED_DIMENSIONS,
        "normalize": True,
    }
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


def _knn_search(vector: list[float], k: int) -> list[dict[str, Any]]:
    client = _get_opensearch()
    query = {
        "size": k,
        "query": {
            "knn": {
                "vector": {
                    "vector": vector,
                    "k": k,
                }
            }
        },
        "_source": ["text_chunk", "source_document", "timestamp", "pii_masked_flag", "chunk_id"],
    }
    try:
        result = client.search(index=OPENSEARCH_INDEX, body=query)
    except Exception as exc:  # noqa: BLE001
        logger.error("OpenSearch k-NN search failed: %s", exc)
        raise

    hits = result.get("hits", {}).get("hits", [])
    logger.info("k-NN retrieved %s hits", len(hits))
    return hits


def _format_context(hits: list[dict[str, Any]]) -> tuple[str, list[dict[str, Any]]]:
    if not hits:
        return "(no relevant context retrieved)", []

    chunks: list[str] = []
    sources: list[dict[str, Any]] = []
    for i, hit in enumerate(hits, start=1):
        src = hit.get("_source") or {}
        text = src.get("text_chunk") or ""
        source_document = src.get("source_document") or "unknown"
        chunks.append(f"[{i}] (source: {source_document})\n{text}")
        sources.append(
            {
                "rank": i,
                "score": hit.get("_score"),
                "source_document": source_document,
                "chunk_id": src.get("chunk_id"),
                "pii_masked_flag": src.get("pii_masked_flag"),
            }
        )
    return "\n\n".join(chunks), sources


def _invoke_claude(system_prompt: str, question: str) -> tuple[str, dict[str, int]]:
    body = {
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": MAX_TOKENS,
        "temperature": 0.2,
        "system": system_prompt,
        "messages": [
            {
                "role": "user",
                "content": [{"type": "text", "text": question}],
            }
        ],
    }
    try:
        response = bedrock.invoke_model(
            modelId=LLM_MODEL_ID,
            contentType="application/json",
            accept="application/json",
            body=json.dumps(body).encode("utf-8"),
        )
        payload = json.loads(response["body"].read())
        content = payload.get("content") or []
        texts = [block.get("text", "") for block in content if block.get("type") == "text"]
        answer = "\n".join(t for t in texts if t).strip()
        if not answer:
            raise ValueError("Claude returned an empty response")
        usage_raw = payload.get("usage") or {}
        usage = {
            "input_tokens": int(usage_raw.get("input_tokens") or 0),
            "output_tokens": int(usage_raw.get("output_tokens") or 0),
        }
        return answer, usage
    except ClientError as exc:
        logger.error("Bedrock Claude InvokeModel failed: %s", exc)
        raise


def _response(status_code: int, body: dict[str, Any]) -> dict[str, Any]:
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Cache-Control": "no-store",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Headers": "Content-Type,X-Api-Key,Authorization",
            "Access-Control-Allow-Methods": "OPTIONS,POST,GET",
        },
        "body": json.dumps(body),
    }


def _redact_event(event: dict[str, Any]) -> dict[str, Any]:
    # Avoid logging full API keys / auth headers
    clone = dict(event)
    headers = dict(clone.get("headers") or {})
    for key in list(headers):
        if key.lower() in {"x-api-key", "authorization"}:
            headers[key] = "***"
    clone["headers"] = headers
    return clone
