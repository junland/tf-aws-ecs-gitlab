mock_provider "aws" {
  override_during = plan
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["us-east-1a", "us-east-1b"]
    }
  }
  mock_data "aws_region" {
    defaults = {
      region = "us-east-1"
    }
  }
  mock_data "aws_partition" {
    defaults = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }
  mock_data "aws_subnet" {
    defaults = {
      availability_zone = "us-east-1a"
    }
  }
  mock_data "aws_vpc" {
    defaults = {
      cidr_block = "10.0.0.0/16"
    }
  }
  mock_data "aws_ssm_parameter" {
    defaults = {
      value = "ami-0123456789abcdef0"
    }
  }
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
  mock_resource "aws_db_instance" {
    defaults = {
      address  = "gitlab-db.example.internal"
      endpoint = "gitlab-db.example.internal:5432"
      master_user_secret = [{
        secret_arn    = "arn:aws:secretsmanager:us-east-1:123456789012:secret:rds-gitlab-AbCdEf"
        kms_key_id    = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000"
        secret_status = "active"
      }]
    }
  }
  mock_resource "aws_elasticache_replication_group" {
    defaults = {
      primary_endpoint_address = "gitlab-redis.example.internal"
    }
  }
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/gitlab-test"
    }
  }
  mock_resource "aws_ebs_volume" {
    defaults = {
      id = "vol-0123456789abcdef0"
    }
  }
  mock_resource "aws_vpc" {
    defaults = {
      id = "vpc-0123456789abcdef0"
    }
  }
  mock_resource "aws_lb" {
    defaults = {
      arn      = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/net/gitlab/0123456789abcdef"
      dns_name = "gitlab-nlb.example.internal"
      zone_id  = "Z26RNL4JYFTOTI"
    }
  }
  mock_resource "aws_lb_target_group" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/gitlab/0123456789abcdef"
    }
  }
  mock_resource "aws_ecs_task_definition" {
    defaults = {
      arn = "arn:aws:ecs:us-east-1:123456789012:task-definition/gitlab:1"
    }
  }
}

variables {
  gitlab_hostname                 = "gitlab.example.com"
  gitlab_image                    = "gitlab/gitlab-ce:18.4.6-ce.0"
  certificate_arn                 = "arn:aws:acm:us-east-1:123456789012:certificate/00000000-0000-0000-0000-000000000000"
  gitlab_root_password_secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:gitlab-root-AbCdEf"
  s3_buckets = {
    artifacts        = "test-gitlab-artifacts"
    uploads          = "test-gitlab-uploads"
    packages         = "test-gitlab-packages"
    lfs              = "test-gitlab-lfs"
    terraform_state  = "test-gitlab-terraform-state"
    dependency_proxy = "test-gitlab-dependency-proxy"
    ci_secure_files  = "test-gitlab-ci-secure-files"
    external_diffs   = "test-gitlab-external-diffs"
  }
}

run "managed_infrastructure" {
  command = plan

  assert {
    condition     = length(aws_subnet.private) == 2 && length(aws_subnet.public) == 2 && length(aws_nat_gateway.this) == 1
    error_message = "Managed networking must create two private/public subnets and a shared NAT gateway."
  }
  assert {
    condition     = aws_instance.host.associate_public_ip_address == false && aws_instance.host.metadata_options[0].http_tokens == "required"
    error_message = "The GitLab host must be private and require IMDSv2."
  }
  assert {
    condition     = aws_ebs_volume.data.encrypted && aws_volume_attachment.data.stop_instance_before_detaching
    error_message = "Persistent data must be encrypted and safely detached."
  }
  assert {
    condition     = aws_ecs_service.gitlab.desired_count == 1 && aws_ecs_service.gitlab.deployment_maximum_percent == 100 && aws_ecs_service.gitlab.deployment_minimum_healthy_percent == 0
    error_message = "GitLab deployments must never run two writers against the same repository volume."
  }
  assert {
    condition     = aws_ecs_task_definition.gitlab.network_mode == "bridge" && jsondecode(aws_ecs_task_definition.gitlab.container_definitions)[0].linuxParameters.sharedMemorySize == 256
    error_message = "The EC2 task must reserve GitLab shared memory."
  }
  assert {
    condition     = length(jsondecode(aws_ecs_task_definition.gitlab.container_definitions)[0].mountPoints) == 3
    error_message = "GitLab configuration, logs, and data must all persist."
  }
  assert {
    condition     = aws_db_instance.postgresql.engine == "postgres" && aws_db_instance.postgresql.storage_encrypted && !aws_db_instance.postgresql.publicly_accessible && aws_db_instance.postgresql.manage_master_user_password && aws_db_instance.postgresql.multi_az
    error_message = "RDS PostgreSQL must be private, encrypted, Multi-AZ, and use a managed password."
  }
  assert {
    condition     = aws_db_instance.postgresql.backup_retention_period == 7 && aws_db_instance.postgresql.deletion_protection && !aws_db_instance.postgresql.skip_final_snapshot && !aws_secretsmanager_secret_rotation.postgresql.rotation_enabled
    error_message = "RDS must preserve backups and avoid uncoordinated password rotation."
  }
  assert {
    condition     = aws_elasticache_replication_group.this.at_rest_encryption_enabled && aws_elasticache_replication_group.this.transit_encryption_enabled && aws_elasticache_replication_group.this.transit_encryption_mode == "required"
    error_message = "Required ElastiCache must encrypt Redis traffic and storage."
  }
  assert {
    condition     = strcontains(jsondecode(aws_ecs_task_definition.gitlab.container_definitions)[0].secrets[0].valueFrom, ":password::")
    error_message = "ECS must select the password field of the RDS-managed JSON secret."
  }
  assert {
    condition     = strcontains(local.gitlab_config, "postgresql['enable'] = false") && strcontains(local.gitlab_config, "redis['enable'] = false") && strcontains(local.gitlab_config, "gitlab_rails['object_store']['enabled'] = true")
    error_message = "GitLab must use required RDS, ElastiCache, and S3 instead of bundled dependencies."
  }
  assert {
    condition     = local.gitlab_settings.postgresql.host == aws_db_instance.postgresql.address && local.gitlab_settings.redis_host == aws_elasticache_replication_group.this.primary_endpoint_address && local.gitlab_settings.s3_buckets == var.s3_buckets
    error_message = "GitLab must receive the managed dependency endpoints and required bucket names."
  }
  assert {
    condition     = length(data.aws_iam_policy_document.s3.statement[0].resources) == 8 && length(data.aws_iam_policy_document.s3.statement[1].resources) == 8
    error_message = "Task S3 access must be scoped to the eight configured buckets and their objects."
  }
  assert {
    condition     = aws_lb_listener.https.protocol == "TLS" && aws_lb_listener.ssh.port == 22 && length(aws_vpc_security_group_ingress_rule.ssh) == 0
    error_message = "NLB must provide TLS and Git-over-SSH, with SSH blocked by default."
  }
  assert {
    condition     = strcontains(local.host_user_data, "[settings.ecs]") && strcontains(local.host_user_data, "cluster = \"gitlab-ecs\"") && strcontains(local.host_user_data, "mode = \"always\"") && strcontains(local.host_user_data, "essential = true") && strcontains(local.host_user_data, base64encode(local.storage_bootstrap))
    error_message = "Bottlerocket TOML must configure ECS and an essential storage bootstrap on every boot."
  }
  assert {
    condition     = data.aws_ssm_parameter.ecs_ami[0].name == "/aws/service/bottlerocket/aws-ecs-2/x86_64/latest/image_id" && !strcontains(local.host_user_data, "source =")
    error_message = "Default AMI and bootstrap image must use supported Bottlerocket ECS defaults."
  }
  assert {
    condition     = alltrue([for volume in aws_ecs_task_definition.gitlab.volume : startswith(volume.host_path, "/mnt/gitlab/")]) && strcontains(local.storage_bootstrap, "/.bottlerocket/rootfs/mnt/gitlab") && strcontains(local.storage_bootstrap, "context=system_u:object_r:local_t:s0")
    error_message = "Storage mounts must propagate into ECS under /mnt with Bottlerocket-compatible SELinux labels."
  }
  assert {
    condition     = strcontains(local.storage_bootstrap, "169.254.169.254/32") && strcontains(local.storage_bootstrap, "-N DOCKER-USER") && strcontains(local.storage_bootstrap, "-I FORWARD 1 -j DOCKER-USER") && strcontains(local.host_user_data, "awsvpc-block-imds = true")
    error_message = "Bootstrap must block bridge IMDS before Docker starts without blocking ECS task credentials."
  }
  assert {
    condition     = length(aws_launch_template.host.block_device_mappings) == 1 && alltrue([for device in aws_launch_template.host.block_device_mappings : device.device_name == "/dev/xvdb" && device.ebs[0].encrypted && device.ebs[0].delete_on_termination])
    error_message = "Bottlerocket runtime storage must be encrypted, disposable, and separate from persistent GitLab EBS."
  }
  assert {
    condition     = output.gitlab_url == "https://gitlab.example.com"
    error_message = "The application URL must use HTTPS."
  }
  assert {
    condition     = contains(local.gitlab_settings.monitoring_cidrs, "10.0.0.0/16")
    error_message = "The GitLab monitoring allowlist must permit NLB health checks originating inside the VPC."
  }
  assert {
    condition     = strcontains(local.gitlab_config, "ENV.fetch('AWS_CONTAINER_CREDENTIALS_RELATIVE_URI')") && strcontains(local.gitlab_config, "gitlab_rails['env'] = task_credentials") && strcontains(local.gitlab_config, "gitlab_workhorse['env'] = task_credentials")
    error_message = "Rails/Sidekiq and Workhorse must retain the ECS credential URI after service supervision clears their environment."
  }
}

run "existing_network_and_dns" {
  command = plan
  variables {
    create_vpc                   = false
    vpc_id                       = "vpc-0123456789abcdef0"
    private_subnet_ids           = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
    public_subnet_ids            = []
    load_balancer_internal       = true
    route53_zone_id              = "Z0123456789ABC"
    gitlab_ssh_cidrs             = ["192.0.2.0/24"]
    ami_id                       = "ami-0123456789abcdef0"
    bottlerocket_bootstrap_image = "public.ecr.aws/bottlerocket/bottlerocket-bootstrap:v0.3.6"
    secret_kms_key_arns          = ["arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000"]
    s3_kms_key_arns              = ["arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000001"]
  }
  assert {
    condition     = length(aws_vpc.this) == 0 && length(aws_subnet.private) == 0 && output.vpc_id == var.vpc_id
    error_message = "Existing-network mode must not create a VPC or subnets."
  }
  assert {
    condition     = aws_lb.this.internal && aws_lb.this.subnets == toset(var.private_subnet_ids)
    error_message = "Internal NLB must use supplied private subnets."
  }
  assert {
    condition     = length(aws_route53_record.gitlab) == 1 && length(aws_vpc_security_group_ingress_rule.ssh) == 1 && length(data.aws_ssm_parameter.ecs_ami) == 0
    error_message = "Optional DNS, SSH access, and AMI overrides must be honored."
  }
  assert {
    condition     = length(data.aws_iam_policy_document.secrets.statement) == 2 && length(data.aws_iam_policy_document.s3.statement) == 3
    error_message = "Custom KMS keys must receive scoped application-secret/S3 permissions."
  }
  assert {
    condition     = strcontains(local.host_user_data, "source = \"public.ecr.aws/bottlerocket/bottlerocket-bootstrap:v0.3.6\"")
    error_message = "Explicit pinned bootstrap image overrides must be honored."
  }
}

run "reject_latest_bootstrap_image" {
  command = plan
  variables {
    bottlerocket_bootstrap_image = "public.ecr.aws/bottlerocket/bottlerocket-bootstrap:latest"
  }
  expect_failures = [var.bottlerocket_bootstrap_image]
}

run "reject_latest_image" {
  command = plan
  variables {
    gitlab_image = "gitlab/gitlab-ce:latest"
  }
  expect_failures = [var.gitlab_image]
}

run "reject_missing_existing_network" {
  command = plan
  variables {
    create_vpc         = false
    private_subnet_ids = ["subnet-0123456789abcdef0"]
  }
  expect_failures = [terraform_data.network_validation]
}

run "reject_invalid_buckets" {
  command = plan
  variables {
    s3_buckets = {
      artifacts        = ""
      uploads          = "test-gitlab-uploads"
      packages         = "test-gitlab-packages"
      lfs              = "test-gitlab-lfs"
      terraform_state  = "test-gitlab-terraform-state"
      dependency_proxy = "test-gitlab-dependency-proxy"
      ci_secure_files  = "test-gitlab-ci-secure-files"
      external_diffs   = "test-gitlab-external-diffs"
    }
  }
  expect_failures = [var.s3_buckets]
}

run "reject_invalid_hostname" {
  command = plan
  variables {
    gitlab_hostname = "https://gitlab.example.com"
  }
  expect_failures = [var.gitlab_hostname]
}

run "reject_invalid_ingress" {
  command = plan
  variables {
    gitlab_ssh_cidrs = ["::/0"]
  }
  expect_failures = [var.gitlab_ssh_cidrs]
}

run "reject_duplicate_azs" {
  command = plan
  variables {
    azs = ["us-east-1a", "us-east-1a"]
  }
  expect_failures = [var.azs]
}

run "reject_too_small_vpc" {
  command = plan
  variables {
    vpc_cidr = "10.0.0.0/24"
  }
  expect_failures = [var.vpc_cidr]
}

run "reject_invalid_resource_prefix" {
  command = plan
  variables {
    name_prefix = "gitlab--test"
  }
  expect_failures = [var.name_prefix]
}
