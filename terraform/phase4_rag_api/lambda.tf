###############################################################################
# RAG query Lambda (VPC private subnets)
###############################################################################

resource "aws_security_group" "lambda_rag" {
  name        = "${var.project_name}-rag-query-sg"
  description = "Egress for RAG query Lambda to VPC endpoints"
  vpc_id      = local.vpc_id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-rag-query-sg"
  })
}

resource "aws_vpc_security_group_egress_rule" "rag_https_vpc" {
  security_group_id = aws_security_group.lambda_rag.id
  description       = "HTTPS to Interface VPC Endpoints / AOSS / Bedrock"
  cidr_ipv4         = local.vpc_cidr
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "rag_https_s3" {
  security_group_id = aws_security_group.lambda_rag.id
  description       = "HTTPS to S3 prefix list (unused by query path; defense in depth)"
  prefix_list_id    = data.aws_prefix_list.s3.id
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "null_resource" "rag_package" {
  triggers = {
    requirements = filemd5("${local.lambda_src_dir}/requirements.txt")
    source       = filemd5("${local.lambda_src_dir}/rag_processor.py")
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
      cp "$SRC/rag_processor.py" "$PKG/"
    EOT
  }
}

data "archive_file" "rag_query" {
  type        = "zip"
  source_dir  = local.lambda_package_dir
  output_path = "${path.module}/build/rag_query.zip"

  depends_on = [null_resource.rag_package]
}

resource "aws_cloudwatch_log_group" "rag_query" {
  name              = "/aws/lambda/${var.project_name}-rag-query"
  retention_in_days = 30
  kms_key_id        = local.kms_key_arn

  tags = local.common_tags
}

resource "aws_lambda_function" "rag_query" {
  function_name = "${var.project_name}-rag-query"
  role          = aws_iam_role.rag_query.arn
  handler       = "rag_processor.handler"
  runtime       = "python3.12"
  timeout       = var.lambda_timeout_seconds
  memory_size   = var.lambda_memory_mb
  architectures = ["x86_64"]

  filename         = data.archive_file.rag_query.output_path
  source_code_hash = data.archive_file.rag_query.output_base64sha256

  environment {
    variables = {
      OPENSEARCH_ENDPOINT = local.opensearch_endpoint
      OPENSEARCH_INDEX    = local.opensearch_index_name
      EMBED_MODEL_ID      = local.embed_model_id
      EMBED_DIMENSIONS    = tostring(local.embed_dimensions)
      LLM_MODEL_ID        = var.llm_model_id
      TOP_K               = tostring(var.top_k)
      MAX_TOKENS          = "1024"
    }
  }

  vpc_config {
    subnet_ids         = local.private_subnet_ids
    security_group_ids = [aws_security_group.lambda_rag.id]
  }

  depends_on = [
    aws_cloudwatch_log_group.rag_query,
    aws_iam_role_policy.rag_query,
    aws_opensearchserverless_access_policy.rag_query_data,
  ]

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-rag-query"
  })
}
