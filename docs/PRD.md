# PRD — Enterprise Secure RAG Assistant

| Field | Value |
|---|---|
| Author | Rishabh Ramteke |
| Status | Implemented (Phases 1–4) |
| Version | 1.0 |
| Last updated | 2026-08-10 |
| Region | `us-east-1` |
| Related docs | [`architecture.md`](architecture.md) · [`threat-model.md`](threat-model.md) · [`ADR-001`](ADR-001-bedrock-haiku-vs-openai.md) · [`ADR-002`](ADR-002-opensearch-serverless-vs-qdrant.md) |

---

## 1. Summary

Employees at regulated companies cannot use public AI assistants on internal documents, because doing so moves confidential material outside the corporate trust boundary. This product gives them a document Q&A assistant where **no data leaves the VPC**: documents are encrypted with a customer-managed key, personally identifiable information is stripped before indexing, and every AWS call travels over PrivateLink rather than the public internet.

A user uploads a PDF or text file, waits under a minute, and asks questions in plain language. The assistant answers **only** from the uploaded corpus and cites which document each answer came from. When the corpus does not contain the answer, it declines rather than guessing.

---

## 2. Problem statement

Enterprises hold large volumes of internal documentation — policies, contracts, runbooks, reports — that employees must search manually. Three constraints block the obvious solution of a commercial AI assistant:

1. **Confidentiality.** Sending internal documents to a third-party API places regulated data outside the company's control and audit boundary.
2. **PII exposure.** Source documents routinely contain names, emails, phone numbers, and account identifiers that must not be embedded into a vector index or replayed in an answer.
3. **Trust in answers.** A general-purpose assistant will confidently invent an answer when it lacks one. In a compliance context, a fabricated answer is worse than no answer.

The result is that employees keep searching by hand, and the documents stay effectively unsearchable.

---

## 3. Goals and non-goals

### Goals

| # | Goal |
|---|---|
| G1 | Answer natural-language questions using only the customer's own uploaded documents |
| G2 | Keep all document content and inference traffic inside the AWS trust boundary |
| G3 | Remove PII from document text before it is embedded or indexed |
| G4 | Refuse to answer rather than hallucinate when the corpus lacks the answer |
| G5 | Return answers fast enough for interactive use, and cite sources so answers are verifiable |
| G6 | Deploy reproducibly as infrastructure-as-code, with a documented idle-cost teardown path |

### Non-goals

| # | Non-goal | Rationale |
|---|---|---|
| N1 | Multi-tenant SaaS with per-customer isolation | Single-account reference architecture; tenancy is a later concern |
| N2 | Per-document access control lists | All indexed content is readable by any authorized caller in v1 |
| N3 | Agentic tool use, browsing, or actions | Deliberately disabled to shrink the prompt-injection blast radius |
| N4 | Formats beyond PDF and plain text | Office and image formats deferred until demand is proven |
| N5 | Conversational memory across turns | Each question is answered independently in v1 |
| N6 | Human-in-the-loop answer review | Out of scope; the refusal behavior is the safety mechanism |

---

## 4. Users and personas

| Persona | Role | Primary need | Success looks like |
|---|---|---|---|
| **Ana — Operations Analyst** | Primary end user | Find a specific fact buried in internal documents | Gets a cited answer in seconds instead of reading three PDFs |
| **Dev — Document Owner** | Uploads source material | Publish documents to the assistant without a data-engineering ticket | Drag, drop, and the document is searchable within a minute |
| **Marcus — Security Architect** | Approver / gatekeeper | Prove data never leaves the trust boundary | Can point to PrivateLink, KMS, and IAM evidence in an audit |
| **Priya — Platform Owner** | Deploys and pays for it | Predictable, controllable spend | Can tear down the expensive tier when idle and rebuild on demand |

---

## 5. User stories and acceptance criteria

### US-1 — Upload a document
> As a **document owner**, I want to upload a PDF or text file so its contents become searchable.

**Acceptance criteria**
- Given a `.pdf` or `.txt` file, when I request an upload, then I receive a short-lived presigned URL scoped to a single object key.
- Given any other file extension, when I request an upload, then the request is rejected before any storage is allocated.
- Given a successful upload, then the object is written under `uploads/` and encrypted with the customer-managed KMS key.
- Given an upload request without a valid API key, then the request is rejected with `403`.

### US-2 — PII is removed before indexing
> As a **security architect**, I want PII stripped before text is embedded, so identifiers never enter the vector index.

**Acceptance criteria**
- Given a document containing names, emails, phone numbers, SSNs, or card numbers, when it is processed, then each detected entity is replaced with a `[REDACTED_<TYPE>]` marker.
- Given redaction has run, then the processed output records which entity types were found and how many.
- Given processed chunks are written to `processed/`, then they are encrypted with the customer-managed key.
- Redaction must occur **before** embedding, not after retrieval.

### US-3 — Ask a question and get a cited answer
> As an **operations analyst**, I want to ask a question in plain language and get an answer I can verify.

**Acceptance criteria**
- Given an indexed corpus, when I submit a question, then I receive an answer grounded in the retrieved passages.
- Given an answer is returned, then it includes the source document for each retrieved passage.
- Given an answer is returned, then the response includes a latency breakdown across embedding, retrieval, and generation.
- Given a request with an empty or missing `question` field, then the API returns `400` with a descriptive error.

### US-4 — Refuse when the answer is not in the corpus
> As a **compliance reviewer**, I want the assistant to decline rather than speculate.

**Acceptance criteria**
- Given a question whose answer is absent from the corpus, then the assistant replies exactly: `I do not have access to that information.`
- Given a prompt instructing the model to ignore its instructions, then the assistant still answers only from retrieved context.
- Generation temperature stays low (0.2) to suppress creative completion.

### US-5 — No public data-plane egress
> As a **security architect**, I need to prove document content never traverses the public internet.

**Acceptance criteria**
- All compute runs in private subnets with no internet gateway or NAT attached.
- S3, Bedrock, Comprehend, SQS, CloudWatch Logs, and OpenSearch are reached over VPC endpoints.
- The vector collection rejects connections that do not originate from the designated VPC endpoint.
- Each function's IAM role grants only the actions that function needs.
- API keys and authorization headers are redacted from application logs.

### US-6 — Control idle cost
> As a **platform owner**, I want to shut off the expensive tier when the system is idle.

**Acceptance criteria**
- The vector tier can be destroyed independently without breaking the upload path.
- A documented procedure exists to disable and re-enable it.
- The dominant idle cost driver is identified and quantified in writing.

---

## 6. Functional requirements

| ID | Requirement | Priority |
|---|---|---|
| FR-1 | Accept `.pdf` and `.txt` uploads via short-lived presigned URLs | P0 |
| FR-2 | Reject unsupported file types at request time | P0 |
| FR-3 | Trigger ingestion automatically on object creation | P0 |
| FR-4 | Extract text from PDF and plain text sources | P0 |
| FR-5 | Detect and mask NAME, EMAIL, PHONE, SSN, and card numbers | P0 |
| FR-6 | Split redacted text into overlapping chunks (500 tokens, 50-token overlap) | P0 |
| FR-7 | Embed chunks and index them for vector search | P0 |
| FR-8 | Retrieve the top 3 nearest chunks per question | P0 |
| FR-9 | Generate an answer constrained to retrieved context | P0 |
| FR-10 | Return source attribution for every answer | P0 |
| FR-11 | Return a per-stage latency breakdown and token usage | P1 |
| FR-12 | Route ingestion failures to a dead-letter queue for replay | P1 |
| FR-13 | Skip objects already under `processed/` to prevent recursive processing | P1 |
| FR-14 | Provide a browser UI for upload and question-asking | P1 |
| FR-15 | Record which chunks were derived from redacted source text | P2 |

## 7. Non-functional requirements

| ID | Requirement | Target |
|---|---|---|
| NFR-1 | End-to-end query latency | p90 under 3s |
| NFR-2 | Time from upload to searchable | Under 60s for a typical document |
| NFR-3 | Encryption at rest | Customer-managed KMS key on all stored objects and the vector index |
| NFR-4 | Network isolation | Zero public data-plane egress |
| NFR-5 | Authentication | API key required on every endpoint |
| NFR-6 | Abuse protection | Throttle and daily quota enforced at the API layer |
| NFR-7 | Query success rate | 100% non-error responses under normal load |
| NFR-8 | Reproducibility | Entire stack deployable from source with no console steps |
| NFR-9 | Observability | Structured logs with secrets redacted |

---

## 8. Success metrics

| Metric | Target | Measured | Status |
|---|---|---|---|
| p50 end-to-end latency | < 2.0s | **1.68s** | Met |
| p90 end-to-end latency | < 3.0s | **2.18s** | Met |
| p99 end-to-end latency | < 4.0s | **2.80s** | Met |
| Query success rate | 100% | **50 / 50** | Met |
| Cost per 1K queries (blended) | Minimize | **~$0.51** | Baseline set |
| Public data-plane egress paths | 0 | **0** | Met |
| Manual deployment steps | 0 | **0** | Met |

Latency decomposition across 50 queries: embedding ~146ms mean, retrieval ~449ms mean, generation ~1160ms mean. Generation dominates, which is why model selection was the highest-leverage cost and latency decision.

---

## 9. Solution overview

**Ingestion.** Browser requests a presigned URL → uploads directly to S3 under `uploads/` → object creation raises an event → a state machine runs PII redaction, then embedding and indexing. Failures divert to a dead-letter queue.

**Query.** Client posts a question → the question is embedded → nearest chunks are retrieved by vector similarity → retrieved passages are injected into a context-only system prompt → the model answers or declines → the response returns the answer, its sources, and timing.

**Trust boundary.** The only public surface is the API gateway, protected by an API key and usage plan. Everything behind it runs in private subnets reaching AWS services over VPC endpoints.

---

## 10. Key decisions and trade-offs

| Decision | Chosen | Rejected | Why | Trade-off accepted |
|---|---|---|---|---|
| Generation model host | Managed AWS inference over PrivateLink | Third-party public API | Keeps data in the trust boundary; native IAM and audit trail | Less cross-vendor model flexibility |
| Model tier | Haiku-class | Sonnet-class | ~3x lower inference cost at the measured prompt mix | Reserve the larger model if answer quality proves insufficient |
| Vector store | Managed serverless vector search | Self-hosted alternative | No cluster operations; native IAM and network policy integration | Meaningful idle floor from the capacity-unit minimum |
| Grounding strategy | Strict context-only prompt with explicit refusal | Open-ended answering | Refusal is safer than fabrication in a compliance setting | Assistant declines some questions a human could infer |
| Agentic capability | Disabled | Tool use / browsing | Removes an entire prompt-injection attack surface | No multi-step reasoning or external lookups |
| Redaction point | Before embedding | After retrieval | PII never reaches the index at all | Irreversible; original text is not recoverable from chunks |

Full reasoning in [ADR-001](ADR-001-bedrock-haiku-vs-openai.md) and [ADR-002](ADR-002-opensearch-serverless-vs-qdrant.md).

---

## 11. Risks

| Risk | Severity | Mitigation | Residual |
|---|---|---|---|
| Prompt injection overrides the system prompt | High | Context-only prompt, low temperature, no tool use, pre-redacted context | Medium — prompting alone is not a complete defense |
| Redaction misses an uncommon PII format | High | Managed PII detection across five entity types, applied pre-index | Low–Medium |
| An authorized caller enumerates the corpus | Medium | API key, throttle, daily quota, access logging | Medium — a shared key cannot attribute per-user intent |
| Idle cost accumulates unnoticed | Medium | Vector tier is independently destroyable; teardown documented | Low |
| Over-broad IAM enables lateral movement | High | Per-function least-privilege roles; infrastructure-as-code is source of truth | Low — console drift is the main exposure |
| Answer quality below expectation | Medium | Latency and success benchmarked; larger model swappable without redesign | Medium — no formal answer-accuracy eval yet |

---

## 12. Release plan

| Phase | Scope | Exit criteria |
|---|---|---|
| 1 | Network, encryption, storage foundation | Private subnets, customer-managed key, bucket, core endpoints in place |
| 2 | Ingestion and PII redaction | Upload produces redacted chunks; failures land in the dead-letter queue |
| 3 | Vector store and embedding | Chunks retrievable by similarity search |
| 4 | Query API and interface | Cited answers returned end to end within the latency target |

---

## 13. Future work

1. Replace the shared API key with per-user identity so access is attributable.
2. Add managed guardrails for prompt-attack and sensitive-information filtering.
3. Document-level access control with filtered retrieval.
4. A labeled answer-accuracy evaluation set, so quality is tracked as rigorously as latency.
5. Alerting on dead-letter queue depth.
6. Expand supported formats once demand justifies the parsing cost.

---

## 14. Open questions

1. What answer-accuracy threshold justifies moving to the larger model tier?
2. Should redaction be configurable per corpus, given some teams need names preserved?
3. Is a 3-chunk retrieval window sufficient for multi-document synthesis questions?
4. What is the acceptable idle spend before automated teardown should trigger?

---

## Appendix — Benchmark detail

50 sequential queries, warm functions, single region.

| Stage | Mean | p50 | p90 | p99 |
|---|---|---|---|---|
| Embedding | 146ms | 138ms | 155ms | 279ms |
| Retrieval | 449ms | 433ms | 671ms | 778ms |
| Generation | 1160ms | 1039ms | 1517ms | 2193ms |
| **Total** | **1755ms** | **1682ms** | **2181ms** | **2799ms** |

Token volume across the run: 9,895 input, 3,136 output. Relative generation cost at that volume — Haiku-class ~$0.026 versus Sonnet-class ~$0.077, the basis for the model-tier decision.
