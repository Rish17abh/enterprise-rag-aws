###############################################################################
# Phase 3 — Vector Storage & Bedrock Embedding Ingestion
#
# Layout:
#   versions.tf / variables.tf / terraform.tfvars / outputs.tf / main.tf
#   remote_state.tf — Phase 1 (+ Phase 2 SG optional)
#   opensearch.tf   — AOSS collection + security policies
#   endpoints.tf    — AOSS VPC endpoint
#   lambda.tf / iam.tf
###############################################################################
