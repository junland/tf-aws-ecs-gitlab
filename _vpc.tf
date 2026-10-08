resource "terraform_data" "network_validation" {
  lifecycle {
    precondition {
      condition = var.create_vpc || (
        var.vpc_id != null && length(var.private_subnet_ids) >= 2 &&
        (var.load_balancer_internal || length(var.public_subnet_ids) >= 2)
      )
      error_message = "Existing networking requires vpc_id, two private subnets, and two public subnets unless the NLB is internal."
    }
  }
}

resource "aws_vpc" "this" {
  count                = var.create_vpc ? 1 : 0
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(local.tags, { Name = var.name_prefix })
}

resource "aws_subnet" "public" {
  count             = var.create_vpc ? 2 : 0
  vpc_id            = local.vpc_id
  availability_zone = local.azs[count.index]
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 101 + count.index)
  tags              = merge(local.tags, { Name = "${var.name_prefix}-public-${count.index + 1}" })
}

resource "aws_subnet" "private" {
  count             = var.create_vpc ? 2 : 0
  vpc_id            = local.vpc_id
  availability_zone = local.azs[count.index]
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 1 + count.index)
  tags              = merge(local.tags, { Name = "${var.name_prefix}-private-${count.index + 1}" })
}

resource "aws_internet_gateway" "this" {
  count  = var.create_vpc ? 1 : 0
  vpc_id = local.vpc_id
  tags   = local.tags
}

resource "aws_route_table" "public" {
  count  = var.create_vpc ? 1 : 0
  vpc_id = local.vpc_id
  tags   = local.tags
}

resource "aws_route" "internet" {
  count                  = var.create_vpc ? 1 : 0
  route_table_id         = aws_route_table.public[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this[0].id
}

resource "aws_route_table_association" "public" {
  count          = var.create_vpc ? 2 : 0
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public[0].id
}

resource "aws_eip" "nat" {
  count  = var.create_vpc ? 1 : 0
  domain = "vpc"
  tags   = local.tags
}

resource "aws_nat_gateway" "this" {
  count         = var.create_vpc ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[0].id
  tags          = local.tags
  depends_on    = [aws_internet_gateway.this]
}

resource "aws_route_table" "private" {
  count  = var.create_vpc ? 1 : 0
  vpc_id = local.vpc_id
  tags   = local.tags
}

resource "aws_route" "nat" {
  count                  = var.create_vpc ? 1 : 0
  route_table_id         = aws_route_table.private[0].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[0].id
}

resource "aws_route_table_association" "private" {
  count          = var.create_vpc ? 2 : 0
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[0].id
}
