###############################################################################
# Phase 2 — Data Ingestion & PII Redaction Pipeline
#
# Layout:
#   versions.tf / variables.tf / terraform.tfvars / outputs.tf / main.tf
#   remote_state.tf — Phase 1 outputs
#   lambda.tf       — PII redactor Lambda (VPC)
#   step_function.tf
#   events.tf       — S3 -> EventBridge -> Step Functions
#   iam.tf / sqs.tf / endpoints.tf
###############################################################################
