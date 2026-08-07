###############################################################################
# Phase 1 — AWS KMS Customer Managed Key (S3, OpenSearch, future data at rest)
###############################################################################

resource "aws_kms_key" "main" {
  description             = "${var.project_name} CMK for S3 and OpenSearch encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  multi_region            = false

  # Least-privilege key policy: account root + service integrations (Logs/SQS/S3)
  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "${var.project_name}-kms-policy"
    Statement = [
      {
        Sid    = "EnableRootAccountAdministration"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowUseOfTheKeyForServicesViaIAM"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
          "kms:CreateGrant"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:CallerAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "AllowCloudWatchLogs"
        Effect = "Allow"
        Principal = {
          Service = "logs.${var.aws_region}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
          }
        }
      },
      {
        Sid    = "AllowSQS"
        Effect = "Allow"
        Principal = {
          Service = "sqs.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "AllowOpenSearchServerless"
        Effect = "Allow"
        Principal = {
          Service = "aoss.amazonaws.com"
        }
        Action = [
          "kms:DescribeKey",
          "kms:CreateGrant"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService"    = "aoss.${var.aws_region}.amazonaws.com"
            "kms:CallerAccount" = data.aws_caller_identity.current.account_id
          }
          Bool = {
            "kms:GrantIsForAWSResource" = "true"
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-cmk"
  })
}

resource "aws_kms_alias" "main" {
  name          = "alias/${var.project_name}-cmk"
  target_key_id = aws_kms_key.main.key_id
}
