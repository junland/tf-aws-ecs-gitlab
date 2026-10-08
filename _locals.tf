locals {
  cluster_name       = "${var.name_prefix}-ecs"
  tags               = merge({ Project = "gitlab", ManagedBy = "terraform" }, var.tags)
  azs                = var.azs == null ? slice(data.aws_availability_zones.available.names, 0, 2) : var.azs
  vpc_id             = var.create_vpc ? aws_vpc.this[0].id : var.vpc_id
  private_subnet_ids = var.create_vpc ? aws_subnet.private[*].id : var.private_subnet_ids
  public_subnet_ids  = var.create_vpc ? aws_subnet.public[*].id : var.public_subnet_ids
  bucket_names       = distinct(values(var.s3_buckets))
  secret_arns        = distinct([aws_db_instance.postgresql.master_user_secret[0].secret_arn, var.gitlab_root_password_secret_arn])

  gitlab_settings = {
    external_url     = "https://${var.gitlab_hostname}"
    hostname         = var.gitlab_hostname
    monitoring_cidrs = ["127.0.0.0/8", "::1/128", data.aws_vpc.selected.cidr_block]
    postgresql = {
      host     = aws_db_instance.postgresql.address
      port     = var.postgresql_port
      database = var.postgresql_database
      username = var.postgresql_username
    }
    redis_host = aws_elasticache_replication_group.this.primary_endpoint_address
    s3_buckets = var.s3_buckets
    s3_region  = data.aws_region.current.region
  }

  gitlab_config = templatefile("${path.module}/templates/gitlab.rb.tftpl", {
    settings_base64 = base64encode(jsonencode(local.gitlab_settings))
  })

  host_user_data = templatefile("${path.module}/templates/user_data.sh.tftpl", {
    cluster_name = aws_ecs_cluster.this.name
    volume_id    = aws_ebs_volume.data.id
  })
}
