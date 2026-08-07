variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "enterprise-rag"
}

variable "phase1_state_path" {
  type    = string
  default = "../phase1_network/terraform.tfstate"
}

variable "phase3_state_path" {
  type    = string
  default = "../phase3_vector/terraform.tfstate"
}

variable "llm_model_id" {
  description = "Bedrock Claude model / inference profile for RAG answers"
  type        = string
  default     = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
}

variable "top_k" {
  description = "k-NN neighbors to retrieve"
  type        = number
  default     = 3
}

variable "lambda_timeout_seconds" {
  type    = number
  default = 60
}

variable "lambda_memory_mb" {
  type    = number
  default = 1024
}

variable "api_stage_name" {
  type    = string
  default = "prod"
}

variable "api_throttle_rate_limit" {
  type    = number
  default = 10
}

variable "api_throttle_burst_limit" {
  type    = number
  default = 20
}

variable "api_quota_limit" {
  description = "Daily request quota for the API key usage plan"
  type        = number
  default     = 1000
}
