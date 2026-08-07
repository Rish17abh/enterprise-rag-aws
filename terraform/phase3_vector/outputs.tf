output "vectorizer_lambda_arn" {
  description = "ARN of the vectorizer Lambda (wired into Phase 2 Step Functions)"
  value       = aws_lambda_function.vectorizer.arn
}

output "vectorizer_lambda_name" {
  description = "Name of the vectorizer Lambda"
  value       = aws_lambda_function.vectorizer.function_name
}

output "opensearch_collection_id" {
  description = "OpenSearch Serverless collection ID"
  value       = aws_opensearchserverless_collection.vectors.id
}

output "opensearch_collection_arn" {
  description = "OpenSearch Serverless collection ARN"
  value       = aws_opensearchserverless_collection.vectors.arn
}

output "opensearch_collection_endpoint" {
  description = "HTTPS endpoint for the vector collection"
  value       = aws_opensearchserverless_collection.vectors.collection_endpoint
}

output "opensearch_index_name" {
  description = "k-NN index name"
  value       = var.index_name
}

output "opensearch_vpc_endpoint_id" {
  description = "AOSS VPC endpoint ID"
  value       = aws_opensearchserverless_vpc_endpoint.aoss.id
}

output "embed_model_id" {
  description = "Bedrock embedding model ID"
  value       = var.embed_model_id
}

output "embed_dimensions" {
  description = "Embedding vector dimensions"
  value       = var.embed_dimensions
}

output "vectorizer_security_group_id" {
  description = "Security group ID for the vectorizer Lambda"
  value       = aws_security_group.lambda_vectorizer.id
}
