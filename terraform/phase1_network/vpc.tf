###############################################################################
# Phase 1 — Foundation: VPC, private/isolated subnets (no IGW / no public subnet)
###############################################################################

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  common_tags = {
    Project = var.project_name
    Phase   = "phase1_network"
  }
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-vpc"
  })
}

# Private application subnets (Lambda, VPC endpoints, Step Functions workers)
resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-private-${local.azs[count.index]}"
    Tier = "private"
  })
}

# Isolated database subnets (future data stores; no IGW/NAT routes)
resource "aws_subnet" "isolated" {
  count = length(var.isolated_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.isolated_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-isolated-${local.azs[count.index]}"
    Tier = "isolated"
  })
}

resource "aws_route_table" "private" {
  count = length(aws_subnet.private)

  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-private-rt-${local.azs[count.index]}"
    Tier = "private"
  })
}

resource "aws_route_table" "isolated" {
  count = length(aws_subnet.isolated)

  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-isolated-rt-${local.azs[count.index]}"
    Tier = "isolated"
  })
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

resource "aws_route_table_association" "isolated" {
  count = length(aws_subnet.isolated)

  subnet_id      = aws_subnet.isolated[count.index].id
  route_table_id = aws_route_table.isolated[count.index].id
}
