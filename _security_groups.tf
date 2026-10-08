resource "aws_security_group" "load_balancer" {
  name_prefix = "${var.name_prefix}-lb-"
  description = "GitLab HTTPS and optional Git-over-SSH ingress"
  vpc_id      = local.vpc_id
  tags        = local.tags
}

resource "aws_security_group" "host" {
  name_prefix = "${var.name_prefix}-host-"
  description = "Private GitLab ECS host; no administrative SSH ingress"
  vpc_id      = local.vpc_id
  tags        = local.tags
}

resource "aws_security_group" "redis" {
  name_prefix = "${var.name_prefix}-redis-"
  description = "Redis accessible only to the GitLab host"
  vpc_id      = local.vpc_id
  tags        = local.tags
}

resource "aws_security_group" "postgresql" {
  name_prefix = "${var.name_prefix}-postgresql-"
  description = "RDS PostgreSQL accessible only to the GitLab host"
  vpc_id      = local.vpc_id
  tags        = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  for_each          = var.gitlab_ingress_cidrs
  security_group_id = aws_security_group.load_balancer.id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "GitLab HTTPS"
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  for_each          = var.gitlab_ssh_cidrs
  security_group_id = aws_security_group.load_balancer.id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  description       = "Git-over-SSH, not host administration"
}

resource "aws_vpc_security_group_ingress_rule" "host" {
  for_each                     = toset(["8080", "2222"])
  security_group_id            = aws_security_group.host.id
  referenced_security_group_id = aws_security_group.load_balancer.id
  ip_protocol                  = "tcp"
  from_port                    = tonumber(each.value)
  to_port                      = tonumber(each.value)
}

resource "aws_vpc_security_group_egress_rule" "load_balancer" {
  for_each                     = toset(["8080", "2222"])
  security_group_id            = aws_security_group.load_balancer.id
  referenced_security_group_id = aws_security_group.host.id
  ip_protocol                  = "tcp"
  from_port                    = tonumber(each.value)
  to_port                      = tonumber(each.value)
}

resource "aws_vpc_security_group_egress_rule" "host" {
  security_group_id = aws_security_group.host.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Image pulls, AWS APIs, dependencies and GitLab outbound integrations"
}

resource "aws_vpc_security_group_ingress_rule" "redis" {
  security_group_id            = aws_security_group.redis.id
  referenced_security_group_id = aws_security_group.host.id
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
}

resource "aws_vpc_security_group_ingress_rule" "postgresql" {
  security_group_id            = aws_security_group.postgresql.id
  referenced_security_group_id = aws_security_group.host.id
  ip_protocol                  = "tcp"
  from_port                    = var.postgresql_port
  to_port                      = var.postgresql_port
}
