variable "aws_region" {
  description = "AWS region (must match Phase 1)"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name prefix (must match Phase 1)"
  type        = string
  default     = "enterprise-rag"
}

variable "phase1_state_path" {
  description = "Path to Phase 1 Terraform state file"
  type        = string
  default     = "../phase1_network/terraform.tfstate"
}

variable "phase3_state_path" {
  description = "Path to Phase 3 Terraform state (vectorizer Lambda ARN)"
  type        = string
  default     = "../phase3_vector/terraform.tfstate"
}

variable "lambda_timeout_seconds" {
  description = "PII redactor Lambda timeout"
  type        = number
  default     = 120
}

variable "lambda_memory_mb" {
  description = "PII redactor Lambda memory"
  type        = number
  default     = 512
}

variable "chunk_size_tokens" {
  description = "Chunk size in approximate tokens (words)"
  type        = number
  default     = 500
}

variable "chunk_overlap_tokens" {
  description = "Overlap between chunks in approximate tokens"
  type        = number
  default     = 50
}
