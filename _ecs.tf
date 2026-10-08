resource "aws_ecs_cluster" "this" {
  name = local.cluster_name
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
  tags = local.tags
}

resource "aws_ebs_volume" "data" {
  availability_zone = data.aws_subnet.host.availability_zone
  type              = "gp3"
  size              = var.data_volume_size
  encrypted         = true
  kms_key_id        = var.kms_key_arn
  tags              = merge(local.tags, { Name = "${var.name_prefix}-data" })
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_launch_template" "host" {
  name_prefix = "${var.name_prefix}-host-"
  # Configure Bottlerocket's disposable runtime disk at launch, without claiming
  # management of the separately attached persistent GitLab volume.
  block_device_mappings {
    device_name = "/dev/xvdb"
    ebs {
      volume_size           = 40
      volume_type           = "gp3"
      encrypted             = true
      kms_key_id            = var.kms_key_arn
      delete_on_termination = true
    }
  }
  tags = local.tags
}

resource "aws_instance" "host" {
  ami                         = var.ami_id == null ? data.aws_ssm_parameter.ecs_ami[0].value : var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = local.private_subnet_ids[0]
  vpc_security_group_ids      = [aws_security_group.host.id]
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.host.name
  user_data_replace_on_change = true
  user_data                   = local.host_user_data
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }
  root_block_device {
    volume_size           = 40
    volume_type           = "gp3"
    encrypted             = true
    kms_key_id            = var.kms_key_arn
    delete_on_termination = true
  }
  launch_template {
    id      = aws_launch_template.host.id
    version = aws_launch_template.host.latest_version
  }
  tags       = merge(local.tags, { Name = "${var.name_prefix}-host" })
  depends_on = [terraform_data.network_validation, aws_route.nat, aws_iam_role_policy_attachment.host]
}

resource "aws_volume_attachment" "data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.data.id
  instance_id = aws_instance.host.id
  # Stop the instance before detaching to avoid corrupting mounted repository data.
  stop_instance_before_detaching = true
}

resource "aws_cloudwatch_log_group" "gitlab" {
  name              = "/ecs/${local.cluster_name}/gitlab"
  retention_in_days = var.log_retention_days
  tags              = local.tags
}

resource "aws_ecs_task_definition" "gitlab" {
  family                   = "${var.name_prefix}-gitlab"
  requires_compatibilities = ["EC2"]
  network_mode             = "bridge"
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  dynamic "volume" {
    for_each = toset(["config", "logs", "data"])
    content {
      name      = volume.value
      host_path = "/mnt/gitlab/${volume.value}"
    }
  }

  container_definitions = jsonencode([{
    name      = "gitlab"
    image     = var.gitlab_image
    essential = true
    hostname  = var.gitlab_hostname
    cpu       = var.gitlab_cpu
    memory    = var.gitlab_memory
    linuxParameters = {
      sharedMemorySize = 256
    }
    portMappings = [
      { containerPort = 80, hostPort = 8080, protocol = "tcp" },
      { containerPort = 22, hostPort = 2222, protocol = "tcp" }
    ]
    mountPoints = [
      { sourceVolume = "config", containerPath = "/etc/gitlab", readOnly = false },
      { sourceVolume = "logs", containerPath = "/var/log/gitlab", readOnly = false },
      { sourceVolume = "data", containerPath = "/var/opt/gitlab", readOnly = false }
    ]
    environment = [
      { name = "GITLAB_OMNIBUS_CONFIG", value = local.gitlab_config }
    ]
    secrets = [
      { name = "GITLAB_POSTGRESQL_PASSWORD", valueFrom = "${aws_db_instance.postgresql.master_user_secret[0].secret_arn}:password::" },
      { name = "GITLAB_INITIAL_ROOT_PASSWORD", valueFrom = var.gitlab_root_password_secret_arn }
    ]
    healthCheck = {
      command     = ["CMD-SHELL", "curl --fail --silent http://127.0.0.1/-/health || exit 1"]
      interval    = 60
      timeout     = 10
      retries     = 5
      startPeriod = 300
    }
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.gitlab.name
        awslogs-region        = data.aws_region.current.region
        awslogs-stream-prefix = "gitlab"
      }
    }
    stopTimeout = 120
  }])
  tags = local.tags
}

resource "aws_ecs_service" "gitlab" {
  name                               = "gitlab"
  cluster                            = aws_ecs_cluster.this.id
  task_definition                    = aws_ecs_task_definition.gitlab.arn
  desired_count                      = 1
  launch_type                        = "EC2"
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100
  health_check_grace_period_seconds  = 900
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.web.arn
    container_name   = "gitlab"
    container_port   = 80
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.ssh.arn
    container_name   = "gitlab"
    container_port   = 22
  }
  ordered_placement_strategy {
    type  = "binpack"
    field = "memory"
  }
  tags = local.tags
  depends_on = [
    aws_volume_attachment.data,
    aws_lb_listener.https,
    aws_lb_listener.ssh,
    aws_iam_role_policy_attachment.execution,
    aws_iam_role_policy.secrets,
    aws_iam_role_policy.s3,
    aws_secretsmanager_secret_rotation.postgresql,
    aws_vpc_security_group_ingress_rule.host,
    aws_vpc_security_group_ingress_rule.redis,
    aws_vpc_security_group_ingress_rule.postgresql,
    aws_vpc_security_group_egress_rule.host,
    aws_vpc_security_group_egress_rule.load_balancer
  ]
}
