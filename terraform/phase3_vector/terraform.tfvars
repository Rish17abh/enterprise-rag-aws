aws_region   = "us-east-1"
project_name = "enterprise-rag"

phase1_state_path = "../phase1_network/terraform.tfstate"
phase2_state_path = "../phase2_ingestion/terraform.tfstate"

collection_name  = "enterprise-rag-vectors"
index_name       = "rag-chunks"
embed_model_id   = "amazon.titan-embed-text-v2:0"
embed_dimensions = 1024

lambda_timeout_seconds = 180
lambda_memory_mb       = 1024
