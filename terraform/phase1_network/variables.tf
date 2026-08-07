variable "aws_region" {
  description = "AWS region for Phase 1 foundation resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short project name used for resource naming and tags"
  type        = string
  default     = "enterprise-rag"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private application subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "isolated_subnet_cidrs" {
  description = "CIDR blocks for isolated database subnets (one per AZ, no IGW/NAT)"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "enable_vpc_flow_logs" {
  description = "Whether to enable VPC Flow Logs to CloudWatch (recommended for SOC2)"
  type        = bool
  default     = false
}
