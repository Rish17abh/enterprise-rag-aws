###############################################################################
# Browser upload support — presign Lambda + S3 CORS
###############################################################################

resource "aws_iam_role" "upload_presign" {
  name = "${var.project_name}-upload-presign-role"

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

resource "aws_iam_role_policy" "upload_presign" {
  name = "${var.project_name}-upload-presign-policy"
  role = aws_iam_role.upload_presign.id

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
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.project_name}-upload-presign*"
      },
      {
        Sid      = "S3PresignPut"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = ["${local.s3_bucket_arn}/uploads/*"]
      },
      {
        Sid    = "KMSForSSE"
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

resource "null_resource" "upload_package" {
  triggers = {
    source = filemd5("${local.upload_src_dir}/presign.py")
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      SRC="${local.upload_src_dir}"
      PKG="${local.upload_package_dir}"
      rm -rf "$PKG"
      mkdir -p "$PKG"
      cp "$SRC/presign.py" "$PKG/"
    EOT
  }
}

data "archive_file" "upload_presign" {
  type        = "zip"
  source_dir  = local.upload_package_dir
  output_path = "${path.module}/build/upload_presign.zip"

  depends_on = [null_resource.upload_package]
}

resource "aws_cloudwatch_log_group" "upload_presign" {
  name              = "/aws/lambda/${var.project_name}-upload-presign"
  retention_in_days = 30
  kms_key_id        = local.kms_key_arn

  tags = local.common_tags
}

resource "aws_lambda_function" "upload_presign" {
  function_name = "${var.project_name}-upload-presign"
  role          = aws_iam_role.upload_presign.arn
  handler       = "presign.handler"
  runtime       = "python3.12"
  timeout       = 15
  memory_size   = 256
  architectures = ["x86_64"]

  filename         = data.archive_file.upload_presign.output_path
  source_code_hash = data.archive_file.upload_presign.output_base64sha256

  environment {
    variables = {
      UPLOAD_BUCKET       = local.s3_bucket_id
      KMS_KEY_ARN         = local.kms_key_arn
      URL_EXPIRES_SECONDS = "300"
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.upload_presign,
    aws_iam_role_policy.upload_presign,
  ]

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-upload-presign"
  })
}

resource "aws_s3_bucket_cors_configuration" "documents" {
  bucket = local.s3_bucket_id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT", "HEAD"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag", "x-amz-server-side-encryption"]
    max_age_seconds = 3000
  }
}
