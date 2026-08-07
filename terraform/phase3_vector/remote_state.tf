data "terraform_remote_state" "phase1" {
  backend = "local"
  config = {
    path = var.phase1_state_path
  }
}

data "terraform_remote_state" "phase2" {
  backend = "local"
  config = {
    path = var.phase2_state_path
  }
}

data "aws_caller_identity" "current" {}

data "aws_prefix_list" "s3" {
  name = "com.amazonaws.${var.aws_region}.s3"
}

locals {
  vpc_id                         = data.terraform_remote_state.phase1.outputs.vpc_id
  vpc_cidr                       = data.terraform_remote_state.phase1.outputs.vpc_cidr
  private_subnet_ids             = data.terraform_remote_state.phase1.outputs.private_subnet_ids
  s3_bucket_id                   = data.terraform_remote_state.phase1.outputs.s3_bucket_id
  s3_bucket_arn                  = data.terraform_remote_state.phase1.outputs.s3_bucket_arn
  kms_key_arn                    = data.terraform_remote_state.phase1.outputs.kms_key_arn
  vpc_endpoint_security_group_id = data.terraform_remote_state.phase1.outputs.vpc_endpoint_security_group_id

  common_tags = {
    Project = var.project_name
    Phase   = "phase3_vector"
  }

  lambda_src_dir     = "${path.module}/../../src/lambda_vectorizer"
  lambda_package_dir = "${path.module}/../../src/lambda_vectorizer/package"

  collection_name = var.collection_name
}
