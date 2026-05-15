resource "aws_db_subnet_group" "this" {
  name        = "${var.project}-${var.environment}-rds-subnet-group"
  description = "DB subnet group for ${var.project}-${var.environment} RDS MySQL"
  subnet_ids  = var.subnet_ids

  tags = {
    Name = "${var.project}-${var.environment}-rds-subnet-group"
  }
}

resource "aws_db_instance" "this" {
  identifier = "${var.project}-${var.environment}-mysql"

  engine         = var.engine
  instance_class = var.instance_class

  allocated_storage = var.allocated_storage
  storage_type      = var.storage_type
  storage_encrypted = true

  db_name  = var.database_name
  username = var.master_username

  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = var.security_group_ids

  publicly_accessible = var.publicly_accessible
  multi_az            = var.multi_az

  backup_retention_period = var.backup_retention_period
  backup_window           = var.backup_window
  maintenance_window      = var.maintenance_window

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : var.final_snapshot_identifier
  copy_tags_to_snapshot     = var.copy_tags_to_snapshot

  auto_minor_version_upgrade = true
  apply_immediately          = true

  tags = {
    Name        = "${var.project}-${var.environment}-mysql"
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
