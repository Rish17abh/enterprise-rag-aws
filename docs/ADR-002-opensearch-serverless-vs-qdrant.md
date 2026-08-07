# ADR-002: OpenSearch Serverless vs self-managed Qdrant for vector storage

- Status: Accepted
- Date: 2026-08-06
- Deciders: Solutions Architecture (Enterprise RAG on AWS)

## Context

Phase 3 requires a vector store for Titan embeddings (1024-d) with k-NN retrieval for RAG. Primary options:

1. **Amazon OpenSearch Serverless (Vector Engine)**
2. **Self-managed Qdrant** (ECS/EKS or VM) behind private networking

## Decision

Use **Amazon OpenSearch Serverless (VECTORSEARCH collection)** with:

- Customer managed KMS encryption (Phase 1 CMK)
- Network policy restricted to the AOSS VPC endpoint
- Data access policies for vectorizer (write) and RAG query (read) IAM roles
- k-NN index `rag-chunks` (FAISS / cosine)

## Rationale

### Scalability vs cluster management

| Dimension | OpenSearch Serverless | Qdrant (self-managed) |
|---|---|---|
| Capacity | OCU auto-scaling | Manual shard/replica planning |
| Patching | AWS managed | Owner responsibility |
| HA | Built-in serverless model | Design multi-AZ yourself |
| AuthZ | IAM + AOSS data policies | API keys / mTLS / custom RBAC |
| VPC isolation | Native AOSS VPC endpoint + policies | Private subnets + SG + service discovery |
| FinOps visibility | Clear OCU line item | Mix of EC2/ECS + EBS + ops time |

For a Solutions Architect portfolio build, Serverless demonstrates managed-service judgment and enterprise IAM/network controls without standing up a stateful cluster.

### Fit with AWS Option A stack

The rest of the system is already AWS-native (S3, Step Functions, Lambda, Bedrock). OpenSearch Serverless keeps vector search inside the same identity, encryption, and PrivateLink model.

## Consequences

### Positive

- No cluster AMI/node management
- Fine-grained collection/index permissions per Lambda role
- Aligns with enterprise procurement of AWS managed analytics/search services

### Negative / trade-offs (important FinOps note)

- **OpenSearch Serverless has a meaningful OCU minimum** (commonly ~2 OCUs even when idle), often ~$175+/month baseline
- Indexing semantics differ slightly from OpenSearch provisioned (e.g., no client-specified document IDs on some index paths)
- Cold-start / policy propagation can add minutes after collection creation

### Mitigation

- Tear down Phase 3 (`terraform -chdir=terraform/phase3_vector destroy`) when idle
- Re-apply Phase 3 + re-wire Phase 2 before ingestion demos
- Call out OCU minimum cost explicitly in README / cost tables (hiring-manager signal)

## Alternatives considered

1. **Amazon OpenSearch provisioned domain** — more control, more ops; deferred
2. **Amazon Aurora PostgreSQL pgvector** — strong SQL option; deferred to keep vector engine explicit in Option A
3. **Qdrant on Fargate** — excellent DX, but shifts HA/backup/IAM integration onto the team

## References

- AWS OpenSearch Serverless Vector Engine docs
- Phase 3 Terraform: `terraform/phase3_vector/`
- Implementation guide FinOps table (baseline vs enterprise spend)
