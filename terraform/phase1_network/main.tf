###############################################################################
# Phase 1 — Foundation Infrastructure
# VPC (private + isolated subnets), KMS CMK, S3 ingestion bucket, PrivateLink
#
# Layout:
#   versions.tf   — Terraform / provider requirements
#   variables.tf  — Input variables
#   terraform.tfvars — Environment values
#   vpc.tf        — VPC, subnets, route tables
#   kms.tf        — Customer managed key
#   s3.tf         — Document bucket + encryption + notification placeholder
#   endpoints.tf  — S3 Gateway + Bedrock + Comprehend Interface endpoints
#   outputs.tf    — Exports for Phase 2+
#
# Apply:
#   cd terraform/phase1_network
#   terraform init
#   terraform plan
#   terraform apply
###############################################################################
