aws_region   = "us-east-1"
project_name = "enterprise-rag"

phase1_state_path = "../phase1_network/terraform.tfstate"
phase3_state_path = "../phase3_vector/terraform.tfstate"

llm_model_id = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
top_k        = 3

lambda_timeout_seconds = 60
lambda_memory_mb       = 1024

api_stage_name           = "prod"
api_throttle_rate_limit  = 50
api_throttle_burst_limit = 100
api_quota_limit          = 5000
