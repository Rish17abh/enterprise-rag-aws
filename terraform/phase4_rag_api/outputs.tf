output "rag_api_id" {
  description = "REST API ID"
  value       = aws_api_gateway_rest_api.rag.id
}

output "rag_api_endpoint" {
  description = "Invoke URL for POST /query"
  value       = "${aws_api_gateway_stage.rag.invoke_url}/query"
}

output "upload_api_endpoint" {
  description = "Invoke URL for POST /upload (presigned URL)"
  value       = "${aws_api_gateway_stage.rag.invoke_url}/upload"
}

output "api_base_url" {
  description = "API Gateway stage base URL"
  value       = aws_api_gateway_stage.rag.invoke_url
}

output "rag_api_stage" {
  description = "API Gateway stage name"
  value       = aws_api_gateway_stage.rag.stage_name
}

output "rag_query_lambda_arn" {
  description = "ARN of the RAG query Lambda"
  value       = aws_lambda_function.rag_query.arn
}

output "rag_query_lambda_name" {
  description = "Name of the RAG query Lambda"
  value       = aws_lambda_function.rag_query.function_name
}

output "rag_api_key_id" {
  description = "API key ID (retrieve value via AWS CLI; not stored in state plaintext output)"
  value       = aws_api_gateway_api_key.rag.id
}

output "rag_api_key_value" {
  description = "API key value for x-api-key header"
  value       = aws_api_gateway_api_key.rag.value
  sensitive   = true
}

output "llm_model_id" {
  value = var.llm_model_id
}

output "top_k" {
  value = var.top_k
}
