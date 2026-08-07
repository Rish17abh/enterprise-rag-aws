###############################################################################
# IAM — least privilege for Lambda, Step Functions, EventBridge
###############################################################################

data "aws_caller_identity" "current" {}

# ---- Lambda execution role ----
resource "aws_iam_role" "pii_redactor" {
  name = "${var.project_name}-pii-redactor-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "pii_redactor" {
  name = "${var.project_name}-pii-redactor-policy"
  role = aws_iam_role.pii_redactor.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.project_name}-pii-redactor*"
      },
      {
        Sid    = "VPCNetworking"
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface",
          "ec2:AssignPrivateIpAddresses",
          "ec2:UnassignPrivateIpAddresses"
        ]
        Resource = "*"
      },
      {
        Sid    = "S3ReadSourceWriteProcessed"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = [
          "${local.s3_bucket_arn}/*"
        ]
      },
      {
        Sid      = "S3ListBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [local.s3_bucket_arn]
      },
      {
        Sid    = "ComprehendPII"
        Effect = "Allow"
        Action = [
          "comprehend:DetectPiiEntities"
        ]
        Resource = "*"
      },
      {
        Sid    = "KMSForS3"
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = [local.kms_key_arn]
      }
    ]
  })
}

# ---- Step Functions role ----
resource "aws_iam_role" "sfn_ingestion" {
  name = "${var.project_name}-sfn-ingestion-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "sfn_ingestion" {
  name = "${var.project_name}-sfn-ingestion-policy"
  role = aws_iam_role.sfn_ingestion.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "InvokePiiRedactorAndVectorizer"
        Effect = "Allow"
        Action = ["lambda:InvokeFunction"]
        Resource = [
          aws_lambda_function.pii_redactor.arn,
          local.vectorizer_lambda_arn
        ]
      },
      {
        Sid      = "SendToDLQ"
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = [aws_sqs_queue.ingestion_dlq.arn]
      },
      {
        Sid    = "KMSForSQS"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = [local.kms_key_arn]
      }
    ]
  })
}

# ---- EventBridge -> Step Functions ----
resource "aws_iam_role" "events_to_sfn" {
  name = "${var.project_name}-events-to-sfn-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "events_to_sfn" {
  name = "${var.project_name}-events-to-sfn-policy"
  role = aws_iam_role.events_to_sfn.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "StartIngestionStateMachine"
        Effect   = "Allow"
        Action   = ["states:StartExecution"]
        Resource = [aws_sfn_state_machine.ingestion.arn]
      }
    ]
  })
}
