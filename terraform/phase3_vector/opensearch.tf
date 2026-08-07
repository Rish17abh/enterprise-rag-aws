###############################################################################
# OpenSearch Serverless Vector Engine — encryption / network / data policies
###############################################################################

resource "aws_opensearchserverless_security_policy" "encryption" {
  name        = "${var.project_name}-vec-enc"
  type        = "encryption"
  description = "Encrypt AOSS collection with Phase 1 CMK"

  policy = jsonencode({
    Rules = [
      {
        ResourceType = "collection"
        Resource     = ["collection/${local.collection_name}"]
      }
    ]
    AWSOwnedKey = false
    KmsARN      = local.kms_key_arn
  })
}

resource "aws_opensearchserverless_vpc_endpoint" "aoss" {
  name               = "${var.project_name}-aoss"
  vpc_id             = local.vpc_id
  subnet_ids         = local.private_subnet_ids
  security_group_ids = [local.vpc_endpoint_security_group_id]
}

resource "aws_opensearchserverless_security_policy" "network" {
  name        = "${var.project_name}-vec-net"
  type        = "network"
  description = "Restrict AOSS access to Phase 1 VPC endpoint only"

  policy = jsonencode([
    {
      Description = "VPC-only access to collection and dashboard"
      Rules = [
        {
          ResourceType = "collection"
          Resource     = ["collection/${local.collection_name}"]
        },
        {
          ResourceType = "dashboard"
          Resource     = ["collection/${local.collection_name}"]
        }
      ]
      SourceVPCEs = [aws_opensearchserverless_vpc_endpoint.aoss.id]
    }
  ])
}

resource "aws_opensearchserverless_access_policy" "data" {
  name        = "${var.project_name}-vec-data"
  type        = "data"
  description = "Allow vectorizer Lambda to manage/index the collection"

  policy = jsonencode([
    {
      Description = "Vectorizer Lambda data-plane access"
      Rules = [
        {
          ResourceType = "collection"
          Resource     = ["collection/${local.collection_name}"]
          Permission = [
            "aoss:CreateCollectionItems",
            "aoss:UpdateCollectionItems",
            "aoss:DescribeCollectionItems"
          ]
        },
        {
          ResourceType = "index"
          Resource     = ["index/${local.collection_name}/*"]
          Permission = [
            "aoss:CreateIndex",
            "aoss:UpdateIndex",
            "aoss:DescribeIndex",
            "aoss:ReadDocument",
            "aoss:WriteDocument"
          ]
        }
      ]
      Principal = [
        aws_iam_role.vectorizer.arn
      ]
    }
  ])
}

resource "aws_opensearchserverless_collection" "vectors" {
  name        = local.collection_name
  type        = "VECTORSEARCH"
  description = "Enterprise RAG vector store"

  depends_on = [
    aws_opensearchserverless_security_policy.encryption,
    aws_opensearchserverless_security_policy.network,
  ]

  tags = merge(local.common_tags, {
    Name = local.collection_name
  })
}

# Allow policies/collection endpoint to settle before Lambda first use
resource "time_sleep" "wait_for_collection" {
  depends_on = [
    aws_opensearchserverless_collection.vectors,
    aws_opensearchserverless_access_policy.data,
  ]
  create_duration = "60s"
}
