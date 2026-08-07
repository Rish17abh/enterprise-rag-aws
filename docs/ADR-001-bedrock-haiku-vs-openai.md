# ADR-001: Bedrock Claude (VPC) vs OpenAI API for enterprise RAG generation

- Status: Accepted
- Date: 2026-08-06
- Deciders: Solutions Architecture (Enterprise RAG on AWS)

## Context

The RAG generation layer must answer employee questions using private corporate document context. Two common options were evaluated:

1. **Amazon Bedrock** (Claude family) invoked from a VPC-attached Lambda over PrivateLink
2. **OpenAI API** (ChatGPT models) invoked over the public internet from application compute

This system also requires PII redaction, private networking, KMS encryption, and portfolio-grade security posture for regulated enterprise demos (SOC2 / HIPAA-aligned patterns).

## Decision

Use **Amazon Bedrock** with a Claude Haiku-class model for generation:

- Deployed model/inference profile: `us.anthropic.claude-haiku-4-5-20251001-v1:0`
- Invoked only from private subnets via the Bedrock Runtime VPC interface endpoint
- Strict system prompt that answers only from retrieved context

OpenAI remains a valid product choice for public SaaS apps, but not for this VPC-isolated enterprise design.

## Rationale

### Security & network isolation

| Concern | Bedrock in VPC | OpenAI API |
|---|---|---|
| Data path | Stays on AWS private network via PrivateLink | Leaves VPC to public HTTPS endpoint |
| IAM control | Native IAM least-privilege on `bedrock:InvokeModel` | API keys / third-party identity |
| Audit | CloudTrail + CloudWatch correlation with AWS resources | External vendor logs |
| Data residency | Selected AWS Region / inference profile | Vendor-controlled endpoint geography |

For an enterprise RAG system that already stores redacted chunks in OpenSearch Serverless and documents in KMS-encrypted S3, keeping generation inside the AWS trust boundary reduces exfiltration and compliance complexity.

### Latency & operations

- Bedrock integrates cleanly with existing Lambda + Step Functions + API Gateway stack
- No additional secret distribution for third-party API keys beyond AWS credentials/IAM roles
- Model choice can be swapped (Haiku ↔ Sonnet) without redesigning networking

### Cost

Haiku-class models are cheaper than Sonnet for high-volume Q&A. Phase 5 benchmarks quantify the token cost delta for the observed prompt mix.

## Consequences

### Positive

- Consistent zero-trust story: S3, Comprehend, Bedrock, OpenSearch are all PrivateLink/VPC constrained
- Stronger enterprise narrative for SOC2/HIPAA network isolation
- Unified IAM + KMS + logging model

### Negative / trade-offs

- Anthropic first-time use (FTU) form is required once per account/org
- Cross-region inference profiles may invoke foundation-model ARNs in other US regions (IAM must allow them)
- Less model shopping flexibility than multi-vendor gateways

## Alternatives considered

1. **OpenAI via NAT Gateway** — rejected due to public egress and weaker VPC isolation story
2. **Self-hosted open-weight LLM on GPU** — rejected for operational cost/complexity vs Bedrock managed inference
3. **Claude Sonnet by default** — deferred; available as a quality upgrade if Haiku answer quality is insufficient

## References

- AWS Well-Architected Security Pillar
- Project `.cursorrules` (PrivateLink + least privilege)
- Phase 4 implementation: `src/lambda_rag_query/rag_processor.py`
