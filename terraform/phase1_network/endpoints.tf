###############################################################################
# Phase 1 — VPC Endpoints (PrivateLink): S3 Gateway + Bedrock + Comprehend
# No traffic to these AWS APIs leaves the AWS private network backbone.
###############################################################################

resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.project_name}-vpce-sg"
  description = "Allow HTTPS from VPC CIDR to Interface VPC Endpoints"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-vpce-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "vpce_https" {
  security_group_id = aws_security_group.vpc_endpoints.id
  description       = "HTTPS from VPC"
  cidr_ipv4         = var.vpc_cidr
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "vpce_egress" {
  security_group_id = aws_security_group.vpc_endpoints.id
  description       = "Allow HTTPS egress within VPC for endpoint ENIs"
  cidr_ipv4         = var.vpc_cidr
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

# Gateway endpoint for S3 — associated with private and isolated route tables
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids = concat(
    aws_route_table.private[*].id,
    aws_route_table.isolated[*].id
  )

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-s3-gateway"
  })
}

# Interface endpoints — Bedrock Runtime, Bedrock Agent, Comprehend
resource "aws_vpc_endpoint" "bedrock_runtime" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.bedrock-runtime"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-bedrock-runtime"
  })
}

resource "aws_vpc_endpoint" "bedrock_agent" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.bedrock-agent"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-bedrock-agent"
  })
}

resource "aws_vpc_endpoint" "comprehend" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.comprehend"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-comprehend"
  })
}
