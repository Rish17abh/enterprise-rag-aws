###############################################################################
# Vectorizer Lambda (VPC) — Titan embeddings -> AOSS
###############################################################################

resource "aws_security_group" "lambda_vectorizer" {
  name        = "${var.project_name}-vectorizer-sg"
  description = "Egress for vectorizer Lambda to VPC endpoints"
  vpc_id      = local.vpc_id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-vectorizer-sg"
  })
}

resource "aws_vpc_security_group_egress_rule" "vectorizer_https_vpc" {
  security_group_id = aws_security_group.lambda_vectorizer.id
  description       = "HTTPS to Interface VPC Endpoints / AOSS"
  cidr_ipv4         = local.vpc_cidr
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "vectorizer_https_s3" {
  security_group_id = aws_security_group.lambda_vectorizer.id
  description       = "HTTPS to S3 via Gateway endpoint"
  prefix_list_id    = data.aws_prefix_list.s3.id
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "null_resource" "vectorizer_package" {
  triggers = {
    requirements = filemd5("${local.lambda_src_dir}/requirements.txt")
    source       = filemd5("${local.lambda_src_dir}/embed_and_index.py")
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      SRC="${local.lambda_src_dir}"
      PKG="${local.lambda_package_dir}"
      rm -rf "$PKG"
      mkdir -p "$PKG"
      python3 -m pip install -r "$SRC/requirements.txt" -t "$PKG" --quiet \
        --platform manylinux2014_x86_64 \
        --implementation cp \
        --python-version 3.12 \
        --only-binary=:all:
      cp "$SRC/embed_and_index.py" "$PKG/"
    EOT
  }
}

data "archive_file" "vectorizer" {
  type        = "zip"
  source_dir  = local.lambda_package_dir
  output_path = "${path.module}/build/vectorizer.zip"

  depends_on = [null_resource.vectorizer_package]
}

resource "aws_cloudwatch_log_group" "vectorizer" {
  name              = "/aws/lambda/${var.project_name}-vectorizer"
  retention_in_days = 30
  kms_key_id        = local.kms_key_arn

  tags = local.common_tags
}

resource "aws_lambda_function" "vectorizer" {
  function_name = "${var.project_name}-vectorizer"
  role          = aws_iam_role.vectorizer.arn
  handler       = "embed_and_index.handler"
  runtime       = "python3.12"
  timeout       = var.lambda_timeout_seconds
  memory_size   = var.lambda_memory_mb
  architectures = ["x86_64"]

  filename         = data.archive_file.vectorizer.output_path
  source_code_hash = data.archive_file.vectorizer.output_base64sha256

  environment {
    variables = {
      OPENSEARCH_ENDPOINT = aws_opensearchserverless_collection.vectors.collection_endpoint
      OPENSEARCH_INDEX    = var.index_name
      EMBED_MODEL_ID      = var.embed_model_id
      EMBED_DIMENSIONS    = tostring(var.embed_dimensions)
      KMS_KEY_ARN         = local.kms_key_arn
    }
  }

  vpc_config {
    subnet_ids         = local.private_subnet_ids
    security_group_ids = [aws_security_group.lambda_vectorizer.id]
  }

  depends_on = [
    aws_cloudwatch_log_group.vectorizer,
    aws_iam_role_policy.vectorizer,
    time_sleep.wait_for_collection,
    aws_opensearchserverless_vpc_endpoint.aoss,
  ]

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-vectorizer"
  })
}
