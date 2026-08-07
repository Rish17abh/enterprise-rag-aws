###############################################################################
# PII Redactor Lambda (Python 3.12, VPC private subnets)
###############################################################################

resource "aws_security_group" "lambda_pii" {
  name        = "${var.project_name}-pii-redactor-sg"
  description = "Egress for PII redactor Lambda to VPC endpoints only"
  vpc_id      = local.vpc_id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-pii-redactor-sg"
  })
}

resource "aws_vpc_security_group_egress_rule" "lambda_https_vpc" {
  security_group_id = aws_security_group.lambda_pii.id
  description       = "HTTPS to Interface VPC Endpoints"
  cidr_ipv4         = local.vpc_cidr
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "lambda_https_s3" {
  security_group_id = aws_security_group.lambda_pii.id
  description       = "HTTPS to S3 via Gateway endpoint prefix list"
  prefix_list_id    = data.aws_prefix_list.s3.id
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "null_resource" "pii_redactor_package" {
  triggers = {
    requirements = filemd5("${local.lambda_src_dir}/requirements.txt")
    source       = filemd5("${local.lambda_src_dir}/pii_redactor.py")
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      SRC="${local.lambda_src_dir}"
      PKG="${local.lambda_package_dir}"
      rm -rf "$PKG"
      mkdir -p "$PKG"
      python3 -m pip install -r "$SRC/requirements.txt" -t "$PKG" --quiet
      cp "$SRC/pii_redactor.py" "$PKG/"
    EOT
  }
}

data "archive_file" "pii_redactor" {
  type        = "zip"
  source_dir  = local.lambda_package_dir
  output_path = "${path.module}/build/pii_redactor.zip"

  depends_on = [null_resource.pii_redactor_package]
}

resource "aws_cloudwatch_log_group" "pii_redactor" {
  name              = "/aws/lambda/${var.project_name}-pii-redactor"
  retention_in_days = 30
  kms_key_id        = local.kms_key_arn

  tags = local.common_tags
}

resource "aws_lambda_function" "pii_redactor" {
  function_name = "${var.project_name}-pii-redactor"
  role          = aws_iam_role.pii_redactor.arn
  handler       = "pii_redactor.handler"
  runtime       = "python3.12"
  timeout       = var.lambda_timeout_seconds
  memory_size   = var.lambda_memory_mb
  architectures = ["x86_64"]

  filename         = data.archive_file.pii_redactor.output_path
  source_code_hash = data.archive_file.pii_redactor.output_base64sha256

  environment {
    variables = {
      KMS_KEY_ARN          = local.kms_key_arn
      PROCESSED_PREFIX     = "processed/"
      CHUNK_SIZE_TOKENS    = tostring(var.chunk_size_tokens)
      CHUNK_OVERLAP_TOKENS = tostring(var.chunk_overlap_tokens)
    }
  }

  vpc_config {
    subnet_ids         = local.private_subnet_ids
    security_group_ids = [aws_security_group.lambda_pii.id]
  }

  depends_on = [
    aws_cloudwatch_log_group.pii_redactor,
    aws_iam_role_policy.pii_redactor,
    aws_vpc_endpoint.logs,
  ]

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-pii-redactor"
  })
}
