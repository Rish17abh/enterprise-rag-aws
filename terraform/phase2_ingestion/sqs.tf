###############################################################################
# Dead-letter queue for failed ingestion / PII redaction executions
###############################################################################

resource "aws_sqs_queue" "ingestion_dlq" {
  name              = "${var.project_name}-ingestion-dlq"
  kms_master_key_id = local.kms_key_arn

  message_retention_seconds = 1209600 # 14 days

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-ingestion-dlq"
  })
}

resource "aws_sqs_queue_policy" "ingestion_dlq" {
  queue_url = aws_sqs_queue.ingestion_dlq.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowStepFunctionsSendMessage"
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.ingestion_dlq.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_sfn_state_machine.ingestion.arn
          }
        }
      }
    ]
  })
}
