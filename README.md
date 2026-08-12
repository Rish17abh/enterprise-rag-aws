# Enterprise Secure RAG on AWS

An end-to-end **Retrieval-Augmented Generation (RAG)** platform built as a security-first AWS reference architecture. Teams can upload documents (PDF/TXT), automatically redact PII, index embeddings in a private vector store, and ask grounded questions over their own corpus.

This repository is a portfolio / interview artifact demonstrating **Solutions Architecture + Terraform + serverless GenAI** skills: modular IaC, least-privilege IAM, private networking, and production-minded operational controls—not a notebook demo wrapped in an API.

---

## Why this exists

Most “chat with your docs” demos skip the hard parts: encryption, network isolation, PII handling, auth, and failure paths. This project focuses on those constraints so the design is credible for enterprise evaluation.

**Useful for**
- Internal knowledge bases (policies, runbooks, SOPs)
- Support / ops assistants that must stay grounded in approved documents
- Security-conscious teams evaluating Bedrock + OpenSearch Serverless
- Hiring managers assessing SA ownership from design → IaC → validation

---

## What it does

| Capability | Behavior |
|---|---|
| Document intake | Browser UI or API requests a short-lived **SigV4** presigned S3 PUT (SSE-KMS) |
| PII minimization | **Amazon Comprehend** detects and redacts sensitive entities before chunking/indexing |
| Vector indexing | **Amazon Titan Text Embeddings V2** (1024-dim) → **OpenSearch Serverless** (k-NN) |
| Question answering | Embed question → retrieve top-k chunks → **Claude on Bedrock** answers **only from context** (or refuses) |
| Access control | API Gateway API key + usage plan (throttle / daily quota) |

---

## Architecture (high level)

```text
Browser / API client
    │
    ├─ POST /upload ──► API Gateway ──► Lambda (presign)
    │                        │
    │                        └─► S3 PUT (SSE-KMS) ──► EventBridge
    │                                                      │
    │                                                 Step Functions
    │                                                      │
    │                                    ┌─────────────────┴─────────────────┐
    │                                    ▼                                   ▼
    │                         Lambda PII redactor                  Lambda vectorizer
    │                         (Comprehend)                         (Titan → AOSS)
    │
    └─ POST /query ──► API Gateway ──► Lambda RAG query
                                         (embed → k-NN → Claude)
```

All Lambda data-plane calls are designed to stay private via **VPC endpoints / PrivateLink** (S3, Bedrock, Comprehend, Logs, SQS, OpenSearch Serverless). There is **no NAT Gateway** in this design.

Detailed Mermaid diagrams: [`docs/architecture.md`](docs/architecture.md)  
Threat model: [`docs/threat-model.md`](docs/threat-model.md)

---

## Design decisions stakeholders usually care about

1. **Trust boundaries first** — Public surface is API Gateway only. Document bytes go to S3 via presign; compute runs in private subnets.
2. **PII before embeddings** — Redact prior to vectorization so identifiers are less likely to land in the index or model context.
3. **Grounding over fluency** — Retrieval-constrained generation with explicit out-of-corpus refusal.
4. **IaC as the contract** — Four Terraform phases with outputs wiring the next stage (repeatable, reviewable, destroyable).
5. **Operational realism** — Step Functions orchestration, DLQ, CloudWatch logging, API throttle/quota, query latency metrics, benchmarks.

---

## Repository layout

```text
enterprise-rag-aws/
├── frontend/                 # Minimal AWS-styled intake + ask UI
├── src/
│   ├── lambda_upload/        # Presign S3 PUT URLs
│   ├── lambda_ingestion/     # PII redaction + chunking
│   ├── lambda_vectorizer/    # Embed + index to OpenSearch Serverless
│   └── lambda_rag_query/     # Retrieve + generate answers
├── terraform/
│   ├── phase1_network/       # VPC, KMS, S3, core VPC endpoints
│   ├── phase2_ingestion/     # EventBridge, Step Functions, PII Lambda, DLQ
│   ├── phase3_vector/        # OpenSearch Serverless + vectorizer Lambda
│   └── phase4_rag_api/       # API Gateway (/upload, /query) + RAG Lambda
├── docs/                     # Architecture, ADRs, threat model
├── tests/                    # Phase 1 verify script + unit tests
└── benchmarks/               # Concurrent RAG request smoke/benchmark
```

---

## Tech stack

| Layer | Choices |
|---|---|
| IaC | Terraform ≥ 1.5 (AWS provider) |
| Runtime | Python 3.12, AWS Lambda |
| Orchestration | Step Functions, EventBridge |
| Storage / crypto | S3 (SSE-KMS), customer-managed KMS CMK |
| AI | Amazon Bedrock (Titan Embed v2, Claude Haiku), Amazon Comprehend |
| Vector DB | OpenSearch Serverless (`VECTORSEARCH`) |
| Edge | API Gateway (REST) + API keys / usage plans |
| Network | Private/isolated subnets, Interface + Gateway VPC endpoints |

---

## Security posture (summary)

- Encryption at rest with **KMS CMK** (S3 SSE-KMS)
- Least-privilege IAM per Lambda / Step Functions role
- PrivateLink-oriented data path (no public Lambda egress via NAT)
- API authentication via **API key** + throttle/quota
- Credential redaction in application logs
- STRIDE-inspired threat model documented in-repo

---

## How the four phases map to delivery

| Phase | Directory | Delivers |
|---|---|---|
| 1 | `terraform/phase1_network` | VPC, subnets, KMS, private S3 docs bucket, Bedrock/Comprehend/S3 endpoints |
| 2 | `terraform/phase2_ingestion` | S3 → EventBridge → Step Functions, PII Lambda, DLQ, Logs/SQS endpoints |
| 3 | `terraform/phase3_vector` | OpenSearch Serverless collection/index, vectorizer Lambda |
| 4 | `terraform/phase4_rag_api` | `/upload` + `/query` APIs, RAG Lambda, S3 CORS for browser uploads |

Apply in order (1 → 2 → 3 → 4). Later phases read earlier state via `terraform_remote_state`.

> **Cost note:** OpenSearch Serverless has meaningful **idle** OCU cost. Phase 3 can be destroyed when the project is idle (`terraform -chdir=terraform/phase3_vector destroy`) and re-applied before demos. Keep Phase 4 `vector_backend_enabled` aligned with whether Phase 3 is live.

---

## Frontend (local demo UI)

A small static UI under `frontend/` supports drag-and-drop upload and Ask.

```bash
./frontend/serve.sh
# open http://127.0.0.1:8080
```

`serve.sh` writes a **gitignored** `config.local.js` with the API base URL + key from Terraform outputs so you are not pasting secrets every session. The key is never committed.

---

## Validation performed

- Phase 1 network / bucket / endpoint verification script (`tests/phase1_verify.sh`)
- End-to-end path: upload → Step Functions success → PII-redacted processed object → authenticated query
- Auth negative path: `/query` without API key → 403
- Out-of-corpus questions refuse rather than hallucinate freely
- Light concurrent benchmark harness (`benchmarks/benchmark_rag.py`)

---

## Architecture Decision Records

- [`docs/ADR-001-bedrock-haiku-vs-openai.md`](docs/ADR-001-bedrock-haiku-vs-openai.md) — why Bedrock Claude for generation
- [`docs/ADR-002-opensearch-serverless-vs-qdrant.md`](docs/ADR-002-opensearch-serverless-vs-qdrant.md) — why OpenSearch Serverless for vectors

---

## What this demonstrates (for hiring managers)

- Ability to translate a GenAI product idea into a **secure AWS reference architecture**
- Comfort with **modular Terraform**, remote state wiring, and phased delivery
- Practical GenAI engineering: embeddings, k-NN retrieval, grounding prompts, refusal behavior
- Security instincts: KMS, PrivateLink, PII redaction, least privilege, threat modeling
- Ownership beyond “happy path”: DLQ, throttles, benchmarks, cost-aware teardown of expensive services

---

## Disclaimer

This is a personal learning / portfolio deployment on a private AWS account. It is **not** a production multi-tenant SaaS. Secrets (API keys, Terraform state) are intentionally excluded from git. Do not commit `*.tfstate`, `.env`, or `frontend/config.local.js`.

---

## Author

Built as a hands-on enterprise RAG / AWS Solutions Architecture project.  
Repository: https://github.com/Rish17abh/enterprise-rag-aws
