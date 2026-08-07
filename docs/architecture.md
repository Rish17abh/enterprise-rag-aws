# Architecture — Enterprise Secure RAG (AWS Option A)

- Date: 2026-08-06
- Scope: Phases 1–4 as implemented in this repo
- Region: `us-east-1`

## High-level architecture

```mermaid
flowchart TB
  subgraph Users["Clients"]
    Browser["Browser UI<br/>frontend/"]
    Caller["API clients"]
  end

  subgraph Edge["Public edge"]
    APIGW["API Gateway<br/>/upload · /query<br/>API key + throttle"]
  end

  subgraph VPC["VPC 10.0.0.0/16 — private + isolated subnets"]
    subgraph Lambdas["Lambda (VPC)"]
      Presign["upload-presign"]
      PII["pii-redactor"]
      Vector["vectorizer"]
      RAG["rag-query"]
    end

    subgraph Endpoints["VPC endpoints / PrivateLink"]
      VPCE["S3 · Bedrock · Comprehend<br/>Logs · SQS · AOSS"]
    end
  end

  subgraph Storage["Data plane"]
    S3["S3 docs bucket<br/>SSE-KMS<br/>uploads/ → processed/"]
    AOSS["OpenSearch Serverless<br/>VECTORSEARCH index"]
    KMS["KMS CMK"]
  end

  subgraph Orchestration["Ingestion orchestration"]
    EB["EventBridge<br/>S3 Object Created"]
    SF["Step Functions"]
    DLQ["SQS DLQ"]
  end

  subgraph AI["AWS AI services"]
    Comp["Comprehend<br/>DetectPiiEntities"]
    Titan["Bedrock Titan Embed v2<br/>1024-dim"]
    Claude["Bedrock Claude<br/>Haiku 4.5"]
  end

  Browser -->|"POST /upload"| APIGW
  Browser -->|"PUT file + SSE-KMS headers"| S3
  Caller -->|"POST /query"| APIGW

  APIGW --> Presign
  APIGW --> RAG
  Presign -->|"presigned PUT URL"| Browser

  S3 --> EB --> SF
  SF --> PII
  PII --> Comp
  PII -->|"write redacted chunks"| S3
  SF --> Vector
  Vector --> Titan
  Vector --> AOSS
  SF -.-> DLQ

  RAG --> Titan
  RAG --> AOSS
  RAG --> Claude

  Lambdas --> VPCE
  KMS -.->|"encrypt at rest"| S3
  KMS -.->|"encrypt at rest"| AOSS
```

## Document intake path

```mermaid
sequenceDiagram
  actor User
  participant UI as Frontend
  participant API as API Gateway
  participant Presign as Lambda upload-presign
  participant S3 as S3 (SSE-KMS)
  participant EB as EventBridge
  participant SF as Step Functions
  participant PII as Lambda pii-redactor
  participant Comp as Comprehend
  participant Vec as Lambda vectorizer
  participant Titan as Bedrock Titan Embed
  participant AOSS as OpenSearch Serverless

  User->>UI: Drop .pdf / .txt
  UI->>API: POST /upload + x-api-key
  API->>Presign: Invoke
  Presign-->>UI: upload_url + required_headers
  UI->>S3: PUT object (SigV4 + aws:kms)
  S3->>EB: Object Created (uploads/)
  EB->>SF: Start execution
  SF->>PII: Redact + chunk
  PII->>Comp: DetectPiiEntities
  PII->>S3: Write processed/ JSON
  SF->>Vec: Embed + index
  Vec->>Titan: Embed chunks
  Vec->>AOSS: k-NN upsert
  Note over SF,AOSS: Ready for retrieval (~15–60s)
```

## Query / RAG path

```mermaid
sequenceDiagram
  actor User
  participant UI as Frontend / client
  participant API as API Gateway
  participant RAG as Lambda rag-query
  participant Titan as Bedrock Titan Embed
  participant AOSS as OpenSearch Serverless
  participant Claude as Bedrock Claude Haiku

  User->>UI: Question
  UI->>API: POST /query + x-api-key
  API->>RAG: Invoke
  RAG->>Titan: Embed question
  RAG->>AOSS: k-NN search (k=3)
  AOSS-->>RAG: Top chunks
  RAG->>Claude: System prompt + CONTEXT + question
  Claude-->>RAG: Grounded answer (or refuse)
  RAG-->>UI: answer + sources + latency_ms
```

## Network & security controls

```mermaid
flowchart LR
  subgraph Public["Internet"]
    Client["Browser / API caller"]
  end

  subgraph Boundary["Trust boundary"]
    APIGW["API Gateway<br/>API key · usage plan"]
  end

  subgraph Private["No public data-plane egress"]
    VPC["Private subnets<br/>Lambdas"]
    VPCE["Interface / gateway endpoints"]
    Svcs["S3 · Bedrock · Comprehend<br/>AOSS · Logs · SQS"]
  end

  Client --> APIGW --> VPC --> VPCE --> Svcs
```

| Control | Implementation |
|---|---|
| Encryption at rest | S3 SSE-KMS, CMK from Phase 1 |
| Upload auth | API key on `POST /upload`; short-lived SigV4 presign |
| Query auth | API key + throttle/quota on API Gateway |
| PII | Comprehend redaction before embed/index |
| Network | PrivateLink/VPC endpoints; no IGW/NAT for Lambdas |
| Isolation | OpenSearch Serverless collection policies; least-privilege IAM |

## Terraform phase map

| Phase | Directory | What it builds |
|---|---|---|
| 1 | `terraform/phase1_network` | VPC, subnets, KMS, S3 docs bucket, core VPC endpoints |
| 2 | `terraform/phase2_ingestion` | PII Lambda, Step Functions, EventBridge, DLQ, more endpoints |
| 3 | `terraform/phase3_vector` | OpenSearch Serverless, vectorizer Lambda, Titan embed wiring |
| 4 | `terraform/phase4_rag_api` | RAG query Lambda, API Gateway `/query` + `/upload`, S3 CORS |

## Runtime components (by name pattern)

- `enterprise-rag-upload-presign`
- `enterprise-rag-pii-redactor`
- `enterprise-rag-vectorizer`
- `enterprise-rag-rag-query`
- Collection: `enterprise-rag-vectors` · Index: `rag-chunks`
- Models: Titan Embed Text v2 (`1024` dims), Claude Haiku 4.5 inference profile

## Viewing this diagram

- **GitHub:** open `docs/architecture.md` — Mermaid renders natively
- **VS Code / Cursor:** Markdown preview with Mermaid support
- **Local:** any Mermaid live editor if you paste a fenced block
