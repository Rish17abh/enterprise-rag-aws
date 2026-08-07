###############################################################################
# API Gateway REST API — API Key auth + Lambda proxy to rag_query
###############################################################################

resource "aws_api_gateway_rest_api" "rag" {
  name        = "${var.project_name}-rag-api"
  description = "Enterprise Secure RAG query API"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-rag-api"
  })
}

resource "aws_api_gateway_resource" "query" {
  rest_api_id = aws_api_gateway_rest_api.rag.id
  parent_id   = aws_api_gateway_rest_api.rag.root_resource_id
  path_part   = "query"
}

resource "aws_api_gateway_resource" "upload" {
  rest_api_id = aws_api_gateway_rest_api.rag.id
  parent_id   = aws_api_gateway_rest_api.rag.root_resource_id
  path_part   = "upload"
}

resource "aws_api_gateway_method" "query_post" {
  rest_api_id      = aws_api_gateway_rest_api.rag.id
  resource_id      = aws_api_gateway_resource.query.id
  http_method      = "POST"
  authorization    = "NONE"
  api_key_required = true
}

resource "aws_api_gateway_method" "upload_post" {
  rest_api_id      = aws_api_gateway_rest_api.rag.id
  resource_id      = aws_api_gateway_resource.upload.id
  http_method      = "POST"
  authorization    = "NONE"
  api_key_required = true
}

resource "aws_api_gateway_method" "query_options" {
  rest_api_id      = aws_api_gateway_rest_api.rag.id
  resource_id      = aws_api_gateway_resource.query.id
  http_method      = "OPTIONS"
  authorization    = "NONE"
  api_key_required = false
}

resource "aws_api_gateway_method" "upload_options" {
  rest_api_id      = aws_api_gateway_rest_api.rag.id
  resource_id      = aws_api_gateway_resource.upload.id
  http_method      = "OPTIONS"
  authorization    = "NONE"
  api_key_required = false
}

resource "aws_api_gateway_integration" "query_post" {
  rest_api_id             = aws_api_gateway_rest_api.rag.id
  resource_id             = aws_api_gateway_resource.query.id
  http_method             = aws_api_gateway_method.query_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.rag_query.invoke_arn
}

resource "aws_api_gateway_integration" "upload_post" {
  rest_api_id             = aws_api_gateway_rest_api.rag.id
  resource_id             = aws_api_gateway_resource.upload.id
  http_method             = aws_api_gateway_method.upload_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.upload_presign.invoke_arn
}

resource "aws_api_gateway_integration" "query_options" {
  rest_api_id = aws_api_gateway_rest_api.rag.id
  resource_id = aws_api_gateway_resource.query.id
  http_method = aws_api_gateway_method.query_options.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_integration" "upload_options" {
  rest_api_id = aws_api_gateway_rest_api.rag.id
  resource_id = aws_api_gateway_resource.upload.id
  http_method = aws_api_gateway_method.upload_options.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "query_options_200" {
  rest_api_id = aws_api_gateway_rest_api.rag.id
  resource_id = aws_api_gateway_resource.query.id
  http_method = aws_api_gateway_method.query_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_method_response" "upload_options_200" {
  rest_api_id = aws_api_gateway_rest_api.rag.id
  resource_id = aws_api_gateway_resource.upload.id
  http_method = aws_api_gateway_method.upload_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "query_options_200" {
  rest_api_id = aws_api_gateway_rest_api.rag.id
  resource_id = aws_api_gateway_resource.query.id
  http_method = aws_api_gateway_method.query_options.http_method
  status_code = aws_api_gateway_method_response.query_options_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Api-Key,Authorization'"
    "method.response.header.Access-Control-Allow-Methods" = "'OPTIONS,POST'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }

  depends_on = [aws_api_gateway_integration.query_options]
}

resource "aws_api_gateway_integration_response" "upload_options_200" {
  rest_api_id = aws_api_gateway_rest_api.rag.id
  resource_id = aws_api_gateway_resource.upload.id
  http_method = aws_api_gateway_method.upload_options.http_method
  status_code = aws_api_gateway_method_response.upload_options_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Api-Key,Authorization'"
    "method.response.header.Access-Control-Allow-Methods" = "'OPTIONS,POST'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }

  depends_on = [aws_api_gateway_integration.upload_options]
}

resource "aws_lambda_permission" "apigw_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.rag_query.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.rag.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigw_invoke_upload" {
  statement_id  = "AllowAPIGatewayInvokeUpload"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.upload_presign.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.rag.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "rag" {
  rest_api_id = aws_api_gateway_rest_api.rag.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.query.id,
      aws_api_gateway_resource.upload.id,
      aws_api_gateway_method.query_post.id,
      aws_api_gateway_method.upload_post.id,
      aws_api_gateway_method.query_options.id,
      aws_api_gateway_method.upload_options.id,
      aws_api_gateway_integration.query_post.id,
      aws_api_gateway_integration.upload_post.id,
      aws_api_gateway_integration.query_options.id,
      aws_api_gateway_integration.upload_options.id,
      aws_api_gateway_integration_response.query_options_200.id,
      aws_api_gateway_integration_response.upload_options_200.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.query_post,
    aws_api_gateway_integration.upload_post,
    aws_api_gateway_integration.query_options,
    aws_api_gateway_integration.upload_options,
    aws_api_gateway_integration_response.query_options_200,
    aws_api_gateway_integration_response.upload_options_200,
  ]
}

resource "aws_api_gateway_stage" "rag" {
  rest_api_id   = aws_api_gateway_rest_api.rag.id
  deployment_id = aws_api_gateway_deployment.rag.id
  stage_name    = var.api_stage_name

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.apigw.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      caller         = "$context.identity.caller"
      user           = "$context.identity.user"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      resourcePath   = "$context.resourcePath"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
      apiKeyId       = "$context.identity.apiKeyId"
    })
  }

  xray_tracing_enabled = false

  tags = local.common_tags

  depends_on = [aws_api_gateway_account.main]
}

resource "aws_cloudwatch_log_group" "apigw" {
  name              = "/aws/apigateway/${var.project_name}-rag-api"
  retention_in_days = 30
  kms_key_id        = local.kms_key_arn

  tags = local.common_tags
}

# Account-level CloudWatch role for API Gateway access logs (idempotent if exists)
resource "aws_iam_role" "apigw_cloudwatch" {
  name = "${var.project_name}-apigw-cloudwatch-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "apigw_cloudwatch" {
  role       = aws_iam_role.apigw_cloudwatch.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_api_gateway_account" "main" {
  cloudwatch_role_arn = aws_iam_role.apigw_cloudwatch.arn
}

resource "aws_api_gateway_method_settings" "all" {
  rest_api_id = aws_api_gateway_rest_api.rag.id
  stage_name  = aws_api_gateway_stage.rag.stage_name
  method_path = "*/*"

  settings {
    metrics_enabled        = true
    logging_level          = "ERROR"
    data_trace_enabled     = false
    throttling_rate_limit  = var.api_throttle_rate_limit
    throttling_burst_limit = var.api_throttle_burst_limit
  }
}

# --- API Key + Usage Plan (guide: IAM / API Key auth) ---
resource "aws_api_gateway_api_key" "rag" {
  name    = "${var.project_name}-rag-key"
  enabled = true

  tags = local.common_tags
}

resource "aws_api_gateway_usage_plan" "rag" {
  name = "${var.project_name}-rag-usage"

  api_stages {
    api_id = aws_api_gateway_rest_api.rag.id
    stage  = aws_api_gateway_stage.rag.stage_name
  }

  throttle_settings {
    rate_limit  = var.api_throttle_rate_limit
    burst_limit = var.api_throttle_burst_limit
  }

  quota_settings {
    limit  = var.api_quota_limit
    period = "DAY"
  }

  tags = local.common_tags
}

resource "aws_api_gateway_usage_plan_key" "rag" {
  key_id        = aws_api_gateway_api_key.rag.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.rag.id
}
