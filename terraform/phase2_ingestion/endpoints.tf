###############################################################################
# CloudWatch Logs VPC endpoint — required for private-subnet Lambda logging
###############################################################################

data "aws_prefix_list" "s3" {
  name = "com.amazonaws.${var.aws_region}.s3"
}

resource "aws_vpc_endpoint" "logs" {
  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.private_subnet_ids
  security_group_ids  = [local.vpc_endpoint_security_group_id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-logs"
  })
}

resource "aws_vpc_endpoint" "sqs" {
  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.sqs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.private_subnet_ids
  security_group_ids  = [local.vpc_endpoint_security_group_id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-sqs"
  })
}
