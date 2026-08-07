output "pii_redactor_lambda_arn" {
  description = "ARN of the PII redactor Lambda"
  value       = aws_lambda_function.pii_redactor.arn
}

output "pii_redactor_lambda_name" {
  description = "Name of the PII redactor Lambda"
  value       = aws_lambda_function.pii_redactor.function_name
}

output "ingestion_state_machine_arn" {
  description = "ARN of the ingestion Step Functions state machine"
  value       = aws_sfn_state_machine.ingestion.arn
}

output "ingestion_state_machine_name" {
  description = "Name of the ingestion Step Functions state machine"
  value       = aws_sfn_state_machine.ingestion.name
}

output "ingestion_dlq_url" {
  description = "URL of the ingestion dead-letter queue"
  value       = aws_sqs_queue.ingestion_dlq.url
}

output "ingestion_dlq_arn" {
  description = "ARN of the ingestion dead-letter queue"
  value       = aws_sqs_queue.ingestion_dlq.arn
}

output "lambda_security_group_id" {
  description = "Security group ID for the PII redactor Lambda"
  value       = aws_security_group.lambda_pii.id
}

output "eventbridge_rule_name" {
  description = "EventBridge rule that starts ingestion on S3 uploads"
  value       = aws_cloudwatch_event_rule.s3_object_created.name
}
