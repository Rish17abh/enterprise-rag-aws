###############################################################################
# Phase 1 — Outputs (consumed by later phases; keep names stable)
###############################################################################

output "vpc_id" {
  description = "ID of the enterprise RAG VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "private_subnet_ids" {
  description = "IDs of private application subnets"
  value       = aws_subnet.private[*].id
}

output "isolated_subnet_ids" {
  description = "IDs of isolated database subnets"
  value       = aws_subnet.isolated[*].id
}

output "private_route_table_ids" {
  description = "Route table IDs for private subnets"
  value       = aws_route_table.private[*].id
}

output "s3_bucket_arn" {
  description = "ARN of the private document ingestion bucket"
  value       = aws_s3_bucket.documents.arn
}

output "s3_bucket_id" {
  description = "Name/ID of the private document ingestion bucket"
  value       = aws_s3_bucket.documents.id
}

output "kms_key_arn" {
  description = "ARN of the CMK used for S3 and OpenSearch encryption"
  value       = aws_kms_key.main.arn
}

output "kms_key_id" {
  description = "ID of the CMK"
  value       = aws_kms_key.main.key_id
}

output "vpc_endpoint_security_group_id" {
  description = "Security group ID attached to Interface VPC Endpoints"
  value       = aws_security_group.vpc_endpoints.id
}

output "s3_vpc_endpoint_id" {
  description = "Gateway VPC Endpoint ID for S3"
  value       = aws_vpc_endpoint.s3.id
}

output "bedrock_runtime_vpc_endpoint_id" {
  description = "Interface VPC Endpoint ID for Bedrock Runtime"
  value       = aws_vpc_endpoint.bedrock_runtime.id
}

output "aws_region" {
  description = "AWS region for this Phase 1 stack"
  value       = var.aws_region
}

output "project_name" {
  description = "Project name prefix used for resource naming"
  value       = var.project_name
}
