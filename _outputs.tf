output "cluster_name" {
  description = "ECS cluster name."
  value       = aws_ecs_cluster.this.name
}

output "cluster_arn" {
  description = "ECS cluster ARN."
  value       = aws_ecs_cluster.this.arn
}

output "service_name" {
  description = "GitLab ECS service name."
  value       = aws_ecs_service.gitlab.name
}

output "task_definition_arn" {
  description = "GitLab task definition ARN."
  value       = aws_ecs_task_definition.gitlab.arn
}

output "gitlab_url" {
  description = "GitLab HTTPS URL; DNS must resolve to the NLB."
  value       = "https://${var.gitlab_hostname}"
}

output "gitlab_ssh_hostname" {
  description = "Git-over-SSH hostname on port 22, accessible only from gitlab_ssh_cidrs."
  value       = var.gitlab_hostname
}

output "load_balancer_dns_name" {
  description = "NLB DNS name for an external DNS alias/CNAME."
  value       = aws_lb.this.dns_name
}

output "load_balancer_zone_id" {
  description = "NLB canonical hosted zone ID."
  value       = aws_lb.this.zone_id
}

output "vpc_id" {
  description = "Managed or supplied VPC ID."
  value       = local.vpc_id
}

output "private_subnet_ids" {
  description = "Managed or supplied private subnet IDs."
  value       = local.private_subnet_ids
}

output "public_subnet_ids" {
  description = "Managed or supplied public subnet IDs."
  value       = local.public_subnet_ids
}

output "host_instance_id" {
  description = "EC2 instance ID for Systems Manager administration."
  value       = aws_instance.host.id
}

output "host_security_group_id" {
  description = "Host security group ID to authorize access to external dependencies."
  value       = aws_security_group.host.id
}

output "data_volume_id" {
  description = "Protected persistent EBS volume containing GitLab configuration, logs and repositories."
  value       = aws_ebs_volume.data.id
}

output "task_role_arn" {
  description = "Application IAM role with access to the required S3 buckets."
  value       = aws_iam_role.task.arn
}

output "elasticache_primary_endpoint" {
  description = "TLS-enabled private Redis endpoint."
  value       = aws_elasticache_replication_group.this.primary_endpoint_address
}

output "postgresql_endpoint" {
  description = "Private RDS PostgreSQL endpoint, including port."
  value       = aws_db_instance.postgresql.endpoint
}

output "postgresql_password_secret_arn" {
  description = "RDS-managed Secrets Manager secret ARN (not the password)."
  value       = aws_db_instance.postgresql.master_user_secret[0].secret_arn
}

output "log_group_name" {
  description = "GitLab CloudWatch log group."
  value       = aws_cloudwatch_log_group.gitlab.name
}
