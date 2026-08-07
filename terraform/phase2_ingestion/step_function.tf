###############################################################################
# Step Functions — PII Redactor -> status check -> Phase 3 placeholder / DLQ
###############################################################################

resource "aws_sfn_state_machine" "ingestion" {
  name     = "${var.project_name}-ingestion"
  role_arn = aws_iam_role.sfn_ingestion.arn

  definition = jsonencode({
    Comment = "Enterprise RAG Phase 2 ingestion: PII redact, chunk, hand off to Phase 3"
    StartAt = "PiiRedactor"
    States = {
      PiiRedactor = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.pii_redactor.arn
          "Payload.$"  = "$"
        }
        OutputPath = "$.Payload"
        Retry = [
          {
            ErrorEquals     = ["Lambda.ServiceException", "Lambda.AWSLambdaException", "Lambda.SdkClientException"]
            IntervalSeconds = 2
            MaxAttempts     = 3
            BackoffRate     = 2
          }
        ]
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            ResultPath  = "$.error"
            Next        = "SendToDLQ"
          }
        ]
        Next = "CheckStatus"
      }

      CheckStatus = {
        Type = "Choice"
        Choices = [
          {
            Variable     = "$.status"
            StringEquals = "SUCCESS"
            Next         = "VectorIndexer"
          },
          {
            Variable     = "$.status"
            StringEquals = "SKIPPED"
            Next         = "IngestionSkipped"
          }
        ]
        Default = "SendToDLQ"
      }

      VectorIndexer = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = local.vectorizer_lambda_arn
          "Payload.$"  = "$"
        }
        OutputPath = "$.Payload"
        Retry = [
          {
            ErrorEquals     = ["Lambda.ServiceException", "Lambda.AWSLambdaException", "Lambda.SdkClientException"]
            IntervalSeconds = 2
            MaxAttempts     = 3
            BackoffRate     = 2
          }
        ]
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            ResultPath  = "$.error"
            Next        = "SendToDLQ"
          }
        ]
        Next = "CheckVectorStatus"
      }

      CheckVectorStatus = {
        Type = "Choice"
        Choices = [
          {
            Variable     = "$.status"
            StringEquals = "SUCCESS"
            Next         = "IngestionSucceeded"
          }
        ]
        Default = "SendToDLQ"
      }

      IngestionSucceeded = {
        Type = "Succeed"
      }

      IngestionSkipped = {
        Type = "Succeed"
      }

      SendToDLQ = {
        Type     = "Task"
        Resource = "arn:aws:states:::sqs:sendMessage"
        Parameters = {
          QueueUrl        = aws_sqs_queue.ingestion_dlq.url
          "MessageBody.$" = "States.JsonToString($)"
        }
        Next = "IngestionFailed"
      }

      IngestionFailed = {
        Type  = "Fail"
        Error = "IngestionFailed"
        Cause = "PII redaction failed; details sent to DLQ"
      }
    }
  })

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.sfn_ingestion.arn}:*"
    include_execution_data = false
    level                  = "ERROR"
  }

  tracing_configuration {
    enabled = false
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-ingestion"
  })

  depends_on = [
    aws_iam_role_policy.sfn_ingestion,
    aws_cloudwatch_log_group.sfn_ingestion,
  ]
}

resource "aws_cloudwatch_log_group" "sfn_ingestion" {
  name              = "/aws/vendedlogs/states/${var.project_name}-ingestion"
  retention_in_days = 30
  kms_key_id        = local.kms_key_arn

  tags = local.common_tags
}

# Step Functions logging requires additional IAM permissions on the SF role
resource "aws_iam_role_policy" "sfn_logging" {
  name = "${var.project_name}-sfn-logging-policy"
  role = aws_iam_role.sfn_ingestion.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "WriteStateMachineLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies",
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      }
    ]
  })
}
