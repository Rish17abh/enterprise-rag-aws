###############################################################################
# IAM — RAG query Lambda least privilege
###############################################################################

resource "aws_iam_role" "rag_query" {
  name = "${var.project_name}-rag-query-role"

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

resource "aws_iam_role_policy" "rag_query" {
  name = "${var.project_name}-rag-query-policy"
  role = aws_iam_role.rag_query.id

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
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.project_name}-rag-query*"
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
        Sid    = "BedrockEmbedAndGenerate"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = [
          # Resource ARNs for foundation models include a trailing :version segment,
          # so wildcards must cover the full resource path.
          "arn:aws:bedrock:*::foundation-model/amazon.titan-embed-text-v2*",
          "arn:aws:bedrock:*::foundation-model/anthropic.claude-haiku*",
          "arn:aws:bedrock:*::foundation-model/anthropic.claude-3-haiku*",
          "arn:aws:bedrock:*:${data.aws_caller_identity.current.account_id}:inference-profile/*",
          "arn:aws:bedrock:*:${data.aws_caller_identity.current.account_id}:application-inference-profile/*"
        ]
      },
      {
        Sid      = "AOSSAPIAccess"
        Effect   = "Allow"
        Action   = ["aoss:APIAccessAll"]
        Resource = [local.opensearch_collection_arn]
      },
      {
        Sid    = "KMSDecrypt"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = [local.kms_key_arn]
      }
    ]
  })
}

# Data-plane access for k-NN search (Phase 3 policy covers vectorizer only)
resource "aws_opensearchserverless_access_policy" "rag_query_data" {
  name        = "${var.project_name}-rag-data"
  type        = "data"
  description = "Allow RAG query Lambda to search the vector index"

  policy = jsonencode([
    {
      Description = "RAG query Lambda read access"
      Rules = [
        {
          ResourceType = "collection"
          Resource     = ["collection/${local.collection_name}"]
          Permission = [
            "aoss:DescribeCollectionItems"
          ]
        },
        {
          ResourceType = "index"
          Resource     = ["index/${local.collection_name}/*"]
          Permission = [
            "aoss:DescribeIndex",
            "aoss:ReadDocument"
          ]
        }
      ]
      Principal = [
        aws_iam_role.rag_query.arn
      ]
    }
  ])
}
