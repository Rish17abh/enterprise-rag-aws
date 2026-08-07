aws_region   = "us-east-1"
project_name = "enterprise-rag"

phase1_state_path = "../phase1_network/terraform.tfstate"
phase3_state_path = "../phase3_vector/terraform.tfstate"

lambda_timeout_seconds = 120
lambda_memory_mb       = 512
chunk_size_tokens      = 500
chunk_overlap_tokens   = 50
