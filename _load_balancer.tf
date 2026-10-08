resource "aws_lb" "this" {
  name                             = "${var.name_prefix}-nlb"
  internal                         = var.load_balancer_internal
  load_balancer_type               = "network"
  subnets                          = var.load_balancer_internal ? local.private_subnet_ids : local.public_subnet_ids
  security_groups                  = [aws_security_group.load_balancer.id]
  enable_cross_zone_load_balancing = true
  tags                             = local.tags
}

resource "aws_lb_target_group" "web" {
  name        = "${var.name_prefix}-web"
  vpc_id      = local.vpc_id
  port        = 8080
  protocol    = "TCP"
  target_type = "instance"
  health_check {
    protocol = "HTTP"
    path     = "/-/readiness"
    port     = "traffic-port"
    matcher  = "200"
  }
  tags = local.tags
}

resource "aws_lb_target_group" "ssh" {
  name        = "${var.name_prefix}-ssh"
  vpc_id      = local.vpc_id
  port        = 2222
  protocol    = "TCP"
  target_type = "instance"
  health_check {
    protocol = "HTTP"
    port     = "8080"
    path     = "/-/readiness"
    matcher  = "200"
  }
  tags = local.tags
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "TLS"
  certificate_arn   = var.certificate_arn
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

resource "aws_lb_listener" "ssh" {
  load_balancer_arn = aws_lb.this.arn
  port              = 22
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ssh.arn
  }
}

resource "aws_route53_record" "gitlab" {
  count   = var.route53_zone_id == null ? 0 : 1
  zone_id = var.route53_zone_id
  name    = var.gitlab_hostname
  type    = "A"
  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = true
  }
}
