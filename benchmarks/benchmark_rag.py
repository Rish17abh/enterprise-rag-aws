#!/usr/bin/env python3
"""
Phase 5 — RAG latency & cost benchmarking.

Sends concurrent questions to the Phase 4 API Gateway endpoint and reports:
  - p50 / p90 / p99 latency for embedding, retrieval, LLM, and end-to-end
  - token usage totals from Claude responses
  - estimated cost comparison: Claude Haiku vs Claude Sonnet (same token mix)

Usage:
  export RAG_API_URL="$(terraform -chdir=terraform/phase4_rag_api output -raw rag_api_endpoint)"
  export RAG_API_KEY="$(terraform -chdir=terraform/phase4_rag_api output -raw rag_api_key_value)"
  python3 benchmarks/benchmark_rag.py --concurrency 50 --requests 50
"""

from __future__ import annotations

import argparse
import json
import os
import statistics
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

# On-demand Bedrock list prices (USD / 1K tokens) — update if AWS pricing changes.
# Sources: AWS Bedrock pricing pages for Anthropic Claude.
PRICE_PER_1K = {
    "haiku": {"input": 0.00025, "output": 0.00125},   # Claude 3 Haiku / comparable Haiku tier
    "haiku_4_5": {"input": 0.001, "output": 0.005},   # Claude Haiku 4.5 (approx; verify on AWS)
    "sonnet": {"input": 0.003, "output": 0.015},      # Claude 3 Sonnet
}

DEFAULT_QUESTIONS = [
    "Who should I contact about the Enterprise RAG policy?",
    "What email is listed for the Enterprise RAG policy?",
    "What phone number appears in the policy document?",
    "What guidance exists about storing SSN values?",
    "Summarize the Enterprise RAG policy contact details.",
    "Is there any credit card information in the documents?",
    "What PII types were redacted from the source material?",
    "What is the CEO salary for Acme Corp in 2019?",
    "List security guidelines mentioned in the uploaded policy.",
    "Where can I find the original unredacted contact details?",
]


@dataclass
class Sample:
    ok: bool
    status: int
    total_ms: float
    embedding_ms: float | None = None
    retrieval_ms: float | None = None
    llm_ms: float | None = None
    input_tokens: int = 0
    output_tokens: int = 0
    error: str = ""
    answer_preview: str = ""


@dataclass
class BenchResult:
    samples: list[Sample] = field(default_factory=list)

    @property
    def successes(self) -> list[Sample]:
        return [s for s in self.samples if s.ok]


def percentile(values: list[float], p: float) -> float:
    if not values:
        return float("nan")
    ordered = sorted(values)
    if len(ordered) == 1:
        return ordered[0]
    k = (len(ordered) - 1) * (p / 100.0)
    f = int(k)
    c = min(f + 1, len(ordered) - 1)
    if f == c:
        return ordered[f]
    return ordered[f] + (ordered[c] - ordered[f]) * (k - f)


def ask(url: str, api_key: str, question: str, timeout: float) -> Sample:
    started = time.perf_counter()
    payload = json.dumps({"question": question}).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=payload,
        headers={
            "Content-Type": "application/json",
            "x-api-key": api_key,
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            body = json.loads(resp.read().decode("utf-8"))
            wall_ms = (time.perf_counter() - started) * 1000.0
            latency = body.get("latency_ms") or {}
            usage = body.get("usage") or {}
            return Sample(
                ok=resp.status == 200 and "answer" in body,
                status=resp.status,
                total_ms=float(latency.get("total") or wall_ms),
                embedding_ms=_maybe_float(latency.get("embedding")),
                retrieval_ms=_maybe_float(latency.get("retrieval")),
                llm_ms=_maybe_float(latency.get("llm")),
                input_tokens=int(usage.get("input_tokens") or 0),
                output_tokens=int(usage.get("output_tokens") or 0),
                answer_preview=str(body.get("answer") or "")[:120],
            )
    except urllib.error.HTTPError as exc:
        wall_ms = (time.perf_counter() - started) * 1000.0
        detail = exc.read().decode("utf-8", errors="replace")[:200]
        return Sample(ok=False, status=exc.code, total_ms=wall_ms, error=detail)
    except Exception as exc:  # noqa: BLE001
        wall_ms = (time.perf_counter() - started) * 1000.0
        return Sample(ok=False, status=0, total_ms=wall_ms, error=str(exc))


def _maybe_float(value: Any) -> float | None:
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def run_benchmark(url: str, api_key: str, requests_n: int, concurrency: int, timeout: float) -> BenchResult:
    questions = [DEFAULT_QUESTIONS[i % len(DEFAULT_QUESTIONS)] for i in range(requests_n)]
    result = BenchResult()
    with ThreadPoolExecutor(max_workers=concurrency) as pool:
        futures = [pool.submit(ask, url, api_key, q, timeout) for q in questions]
        for fut in as_completed(futures):
            result.samples.append(fut.result())
    return result


def summarize_latency(name: str, values: list[float]) -> dict[str, float]:
    if not values:
        return {"count": 0}
    return {
        "count": len(values),
        "mean_ms": round(statistics.fmean(values), 2),
        "p50_ms": round(percentile(values, 50), 2),
        "p90_ms": round(percentile(values, 90), 2),
        "p99_ms": round(percentile(values, 99), 2),
        "max_ms": round(max(values), 2),
    }


def cost_table(input_tokens: int, output_tokens: int) -> list[dict[str, Any]]:
    rows = []
    for label, prices in (
        ("Claude Haiku 3 (reference)", PRICE_PER_1K["haiku"]),
        ("Claude Haiku 4.5 (deployed family)", PRICE_PER_1K["haiku_4_5"]),
        ("Claude 3 Sonnet (alternative)", PRICE_PER_1K["sonnet"]),
    ):
        input_cost = (input_tokens / 1000.0) * prices["input"]
        output_cost = (output_tokens / 1000.0) * prices["output"]
        rows.append(
            {
                "model": label,
                "input_tokens": input_tokens,
                "output_tokens": output_tokens,
                "input_cost_usd": round(input_cost, 6),
                "output_cost_usd": round(output_cost, 6),
                "total_cost_usd": round(input_cost + output_cost, 6),
            }
        )
    return rows


def print_report(result: BenchResult, output_json: Path | None) -> None:
    ok = result.successes
    fail = [s for s in result.samples if not s.ok]
    print("\n=== Phase 5 RAG Benchmark ===")
    print(f"requests={len(result.samples)} success={len(ok)} failed={len(fail)}")

    def col(getter) -> list[float]:
        vals = []
        for s in ok:
            v = getter(s)
            if v is not None:
                vals.append(v)
        return vals

    latency = {
        "embedding": summarize_latency("embedding", col(lambda s: s.embedding_ms)),
        "retrieval": summarize_latency("retrieval", col(lambda s: s.retrieval_ms)),
        "llm": summarize_latency("llm", col(lambda s: s.llm_ms)),
        "total": summarize_latency("total", col(lambda s: s.total_ms)),
    }

    print("\nLatency (ms)")
    print(f"{'stage':<12} {'n':>5} {'mean':>10} {'p50':>10} {'p90':>10} {'p99':>10} {'max':>10}")
    for stage, stats in latency.items():
        if not stats.get("count"):
            print(f"{stage:<12} {'0':>5}")
            continue
        print(
            f"{stage:<12} {stats['count']:>5} {stats['mean_ms']:>10.2f} "
            f"{stats['p50_ms']:>10.2f} {stats['p90_ms']:>10.2f} "
            f"{stats['p99_ms']:>10.2f} {stats['max_ms']:>10.2f}"
        )

    input_tokens = sum(s.input_tokens for s in ok)
    output_tokens = sum(s.output_tokens for s in ok)
    rows = cost_table(input_tokens, output_tokens)

    print("\nCost comparison (same observed token mix)")
    print(f"{'model':<36} {'in_tok':>8} {'out_tok':>8} {'total_usd':>12}")
    for row in rows:
        print(
            f"{row['model']:<36} {row['input_tokens']:>8} {row['output_tokens']:>8} "
            f"{row['total_cost_usd']:>12.6f}"
        )

    if fail:
        print("\nSample failures:")
        for s in fail[:5]:
            print(f"  status={s.status} error={s.error[:160]}")

    report = {
        "summary": {
            "requests": len(result.samples),
            "success": len(ok),
            "failed": len(fail),
            "input_tokens": input_tokens,
            "output_tokens": output_tokens,
        },
        "latency_ms": latency,
        "cost_comparison": rows,
    }
    if output_json:
        output_json.parent.mkdir(parents=True, exist_ok=True)
        output_json.write_text(json.dumps(report, indent=2), encoding="utf-8")
        print(f"\nWrote {output_json}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Benchmark Enterprise RAG API latency and cost")
    parser.add_argument("--url", default=os.environ.get("RAG_API_URL", ""))
    parser.add_argument("--api-key", default=os.environ.get("RAG_API_KEY", ""))
    parser.add_argument("--requests", type=int, default=50)
    parser.add_argument("--concurrency", type=int, default=50)
    parser.add_argument("--timeout", type=float, default=60.0)
    parser.add_argument(
        "--output",
        default=str(Path(__file__).resolve().parent / "results" / "benchmark_latest.json"),
    )
    args = parser.parse_args()

    if not args.url or not args.api_key:
        print(
            "ERROR: set RAG_API_URL and RAG_API_KEY (or pass --url / --api-key)",
            file=sys.stderr,
        )
        return 2

    print(
        f"Running {args.requests} requests at concurrency={args.concurrency} against {args.url}"
    )
    result = run_benchmark(args.url, args.api_key, args.requests, args.concurrency, args.timeout)
    print_report(result, Path(args.output))
    return 0 if any(s.ok for s in result.samples) else 1


if __name__ == "__main__":
    raise SystemExit(main())
