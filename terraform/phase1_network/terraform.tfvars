aws_region   = "us-east-1"
project_name = "enterprise-rag"
vpc_cidr     = "10.0.0.0/16"

private_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
isolated_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]

# Set true after CloudWatch Log Group permissions are reviewed
enable_vpc_flow_logs = false
