variable "aws_region" {
  description = "AWS region (must match Phase 1/2)"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name prefix"
  type        = string
  default     = "enterprise-rag"
}

variable "phase1_state_path" {
  description = "Path to Phase 1 Terraform state"
  type        = string
  default     = "../phase1_network/terraform.tfstate"
}

variable "phase2_state_path" {
  description = "Path to Phase 2 Terraform state"
  type        = string
  default     = "../phase2_ingestion/terraform.tfstate"
}

variable "collection_name" {
  description = "OpenSearch Serverless collection name (max 32 chars)"
  type        = string
  default     = "enterprise-rag-vectors"
}

variable "index_name" {
  description = "k-NN index name inside the collection"
  type        = string
  default     = "rag-chunks"
}

variable "embed_model_id" {
  description = "Bedrock embedding model ID"
  type        = string
  default     = "amazon.titan-embed-text-v2:0"
}

variable "embed_dimensions" {
  description = "Titan V2 embedding dimensions (1024, 512, or 256)"
  type        = number
  default     = 1024
}

variable "lambda_timeout_seconds" {
  type    = number
  default = 180
}

variable "lambda_memory_mb" {
  type    = number
  default = 1024
}
