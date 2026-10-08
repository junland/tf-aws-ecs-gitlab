resource "aws_db_subnet_group" "postgresql" {
  name       = "${var.name_prefix}-postgresql"
  subnet_ids = local.private_subnet_ids
  tags       = local.tags
}

resource "aws_db_instance" "postgresql" {
  identifier                      = "${var.name_prefix}-postgresql"
  engine                          = "postgres"
  engine_version                  = var.postgresql_engine_version
  instance_class                  = var.postgresql_instance_class
  db_name                         = var.postgresql_database
  username                        = var.postgresql_username
  manage_master_user_password     = true
  port                            = var.postgresql_port
  allocated_storage               = var.postgresql_allocated_storage
  max_allocated_storage           = 1000
  storage_type                    = "gp3"
  storage_encrypted               = true
  kms_key_id                      = var.kms_key_arn
  db_subnet_group_name            = aws_db_subnet_group.postgresql.name
  vpc_security_group_ids          = [aws_security_group.postgresql.id]
  publicly_accessible             = false
  multi_az                        = var.postgresql_multi_az
  backup_retention_period         = 7
  copy_tags_to_snapshot           = true
  deletion_protection             = var.postgresql_deletion_protection
  skip_final_snapshot             = false
  final_snapshot_identifier       = coalesce(var.postgresql_final_snapshot_identifier, "${var.name_prefix}-postgresql-final")
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  auto_minor_version_upgrade      = true
  tags                            = local.tags
}

# ECS injects secrets only at task startup; unsynchronized rotation breaks reconnects.
resource "aws_secretsmanager_secret_rotation" "postgresql" {
  secret_id        = aws_db_instance.postgresql.master_user_secret[0].secret_arn
  rotation_enabled = false
}
