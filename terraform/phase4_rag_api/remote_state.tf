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

data "aws_caller_identity" "current" {}

data "aws_prefix_list" "s3" {
  name = "com.amazonaws.${var.aws_region}.s3"
}

locals {
  vpc_id                         = data.terraform_remote_state.phase1.outputs.vpc_id
  vpc_cidr                       = data.terraform_remote_state.phase1.outputs.vpc_cidr
  private_subnet_ids             = data.terraform_remote_state.phase1.outputs.private_subnet_ids
  kms_key_arn                    = data.terraform_remote_state.phase1.outputs.kms_key_arn
  s3_bucket_id                   = data.terraform_remote_state.phase1.outputs.s3_bucket_id
  s3_bucket_arn                  = data.terraform_remote_state.phase1.outputs.s3_bucket_arn
  vpc_endpoint_security_group_id = data.terraform_remote_state.phase1.outputs.vpc_endpoint_security_group_id

  opensearch_endpoint       = data.terraform_remote_state.phase3.outputs.opensearch_collection_endpoint
  opensearch_collection_arn = data.terraform_remote_state.phase3.outputs.opensearch_collection_arn
  opensearch_collection_id  = data.terraform_remote_state.phase3.outputs.opensearch_collection_id
  opensearch_index_name     = data.terraform_remote_state.phase3.outputs.opensearch_index_name
  embed_model_id            = data.terraform_remote_state.phase3.outputs.embed_model_id
  embed_dimensions          = data.terraform_remote_state.phase3.outputs.embed_dimensions

  collection_name = "enterprise-rag-vectors"

  common_tags = {
    Project = var.project_name
    Phase   = "phase4_rag_api"
  }

  lambda_src_dir     = "${path.module}/../../src/lambda_rag_query"
  lambda_package_dir = "${path.module}/../../src/lambda_rag_query/package"

  upload_src_dir     = "${path.module}/../../src/lambda_upload"
  upload_package_dir = "${path.module}/../../src/lambda_upload/package"
}
