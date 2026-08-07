###############################################################################
# Consume Phase 1 + Phase 3 outputs — do not hardcode VPC/S3/KMS/Lambda IDs
###############################################################################

data "terraform_remote_state" "phase1" {
  backend = "local"

  config = {
    path = var.phase1_state_path
  }
}

data "terraform_remote_state" "phase3" {
  backend = "local"

  config = {
    path = var.phase3_state_path
  }
}

locals {
  vpc_id                         = data.terraform_remote_state.phase1.outputs.vpc_id
  vpc_cidr                       = data.terraform_remote_state.phase1.outputs.vpc_cidr
  private_subnet_ids             = data.terraform_remote_state.phase1.outputs.private_subnet_ids
  private_route_table_ids        = data.terraform_remote_state.phase1.outputs.private_route_table_ids
  s3_bucket_id                   = data.terraform_remote_state.phase1.outputs.s3_bucket_id
  s3_bucket_arn                  = data.terraform_remote_state.phase1.outputs.s3_bucket_arn
  kms_key_arn                    = data.terraform_remote_state.phase1.outputs.kms_key_arn
  vpc_endpoint_security_group_id = data.terraform_remote_state.phase1.outputs.vpc_endpoint_security_group_id

  vectorizer_lambda_arn = data.terraform_remote_state.phase3.outputs.vectorizer_lambda_arn

  common_tags = {
    Project = var.project_name
    Phase   = "phase2_ingestion"
  }

  lambda_src_dir     = "${path.module}/../../src/lambda_ingestion"
  lambda_package_dir = "${path.module}/../../src/lambda_ingestion/package"
}
