resource "aws_elasticache_subnet_group" "this" {
  name       = "${var.name_prefix}-redis"
  subnet_ids = local.private_subnet_ids
  tags       = local.tags
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id       = "${var.name_prefix}-redis"
  description                = "Private GitLab Redis"
  engine                     = "redis"
  engine_version             = var.elasticache_engine_version
  node_type                  = var.elasticache_node_type
  port                       = 6379
  num_cache_clusters         = 1
  automatic_failover_enabled = false
  subnet_group_name          = aws_elasticache_subnet_group.this.name
  security_group_ids         = [aws_security_group.redis.id]
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  transit_encryption_mode    = "required"
  kms_key_id                 = var.kms_key_arn
  snapshot_retention_limit   = 7
  tags                       = local.tags
}
