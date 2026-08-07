# Threat Model — Enterprise Secure RAG (AWS Option A)

- Date: 2026-08-06
- Scope: Phases 1–4 (ingestion, PII redaction, vectorization, RAG query API)
- Method: STRIDE-inspired analysis focused on RAG-specific risks

## System summary

```text
S3 upload (.pdf/.txt)
  -> EventBridge
  -> Step Functions
  -> Lambda PII redactor (Comprehend) -> s3://.../processed/
  -> Lambda vectorizer (Titan embed) -> OpenSearch Serverless
User question
  -> API Gateway (API key)
  -> Lambda RAG query (Titan embed + k-NN + Claude)
```

All data-plane AWS API calls are designed to stay private via VPC endpoints (S3 gateway, Bedrock, Comprehend, Logs, SQS, AOSS).

## Assets

| Asset | Sensitivity |
|---|---|
| Source documents in S3 | Confidential / may contain PII |
| Processed chunks | Confidential (PII-redacted, still business-sensitive) |
| Vector index | Confidential embeddings + chunk text |
| API answers | Confidential derivative data |
| API keys / IAM roles | High |

## Trust boundaries

1. **Internet → API Gateway** (public regional endpoint, API key required)
2. **VPC private subnets** (Lambdas, VPC endpoints)
3. **AWS managed services** (Bedrock, Comprehend, AOSS, S3)
4. **Account IAM boundary**

## Key threats & mitigations

### 1) Prompt injection (user → LLM)

**Threat:** Attacker crafts a question that tries to override the system prompt (“ignore previous instructions…”) or exfiltrate hidden context.

**Impact:** Policy bypass, sensitive chunk disclosure, incorrect authoritative answers.

**Mitigations in this design:**
- Strict system prompt: answer **only** from provided CONTEXT; otherwise refuse
- Temperature kept low (0.2)
- No tool-calling / browsing enabled
- Retrieved context is already PII-redacted

**Residual risk:** Medium — prompt injection against RAG is not fully solvable with prompting alone. Future hardening: output filters, allowlisted intents, Bedrock Guardrails.

### 2) PII leakage

**Threats:**
- PII survives into embeddings/index
- Model quotes residual identifiers
- Logs capture raw prompts/documents

**Mitigations:**
- Comprehend `DetectPiiEntities` redaction before chunking (`[REDACTED_<TYPE>]`)
- Processed objects written under `processed/` with SSE-KMS
- RAG Lambda redacts `x-api-key` / `Authorization` from logs
- API access logs exclude payload bodies

**Residual risk:** Low–Medium — Comprehend may miss uncommon PII formats; defense-in-depth still needed for highly regulated corpora.

### 3) Data exfiltration via retrieval

**Threat:** Authenticated API caller asks many targeted questions to reconstruct documents.

**Mitigations:**
- API key + usage plan throttle/quota
- Context-only answering reduces free-form hallucination, but not authorized enumeration
- CloudWatch/API logs for anomaly review

**Residual risk:** Medium for any shared API key. Future: Cognito/IAM auth per user, per-document ACLs, rate limits per principal.

### 4) IAM privilege boundaries

**Threat:** Over-broad roles allow lateral movement (read all S3, invoke any model, write any index).

**Mitigations (current least-privilege posture):**
- PII Lambda: S3 read/write on ingestion bucket, `comprehend:DetectPiiEntities`, KMS, VPC ENI perms
- Vectorizer Lambda: S3 read `processed/*`, `bedrock:InvokeModel` (Titan), `aoss:APIAccessAll` on one collection
- RAG Lambda: Bedrock invoke (Titan + Claude inference profile), AOSS read-only data policy, no S3 write
- AOSS network policy: SourceVPCEs only (no public collection endpoint)

**Residual risk:** Low if Terraform remains source of truth; drift via console clicks is the main risk.

### 5) Supply-chain / dependency risk in Lambdas

**Threat:** Compromised Python dependency in Lambda package.

**Mitigations:** Pin versions in `requirements.txt`; build manylinux wheels for Python 3.12; keep packages minimal (`boto3` runtime + `opensearch-py`).

### 6) Availability / cost abuse

**Threat:** Flood API to drive Bedrock/OpenSearch spend.

**Mitigations:** API Gateway usage plan throttle + daily quota; Stage method settings; ability to disable API key quickly.

**FinOps note:** OpenSearch Serverless OCU minimum dominates idle cost — destroy Phase 3 when not demoing.

## Abuse cases (quick)

| Abuse case | Expected system behavior |
|---|---|
| Question unrelated to corpus | Refuse: “I do not have access to that information.” |
| Upload of PII-heavy TXT | Redacted before indexing |
| Call without API key | `403 Forbidden` |
| Direct public access to OpenSearch | Denied by network policy |

## Recommended next hardening (not yet implemented)

1. Replace shared API key with IAM SigV4 or Cognito user pools
2. Add Bedrock Guardrails (prompt attack + sensitive info filters)
3. Document-level access control in metadata + filtered k-NN queries
4. DLQ alarm + Security Hub / GuardDuty findings for the account
5. Formal threat-model review with data owners (STRIDE workshop)

## Owners

- Architecture & controls: Principal AWS Solutions Architect (project role)
- Runtime evidence: Phase 4/5 smoke tests and CloudWatch logs
