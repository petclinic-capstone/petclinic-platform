output "db_instance_identifier" {
  description = "RDS DB instance identifier"
  value       = aws_db_instance.this.identifier
}

output "db_instance_arn" {
  description = "RDS DB instance ARN"
  value       = aws_db_instance.this.arn
}

output "db_endpoint" {
  description = "RDS endpoint address"
  value       = aws_db_instance.this.address
}

output "db_port" {
  description = "RDS endpoint port"
  value       = aws_db_instance.this.port
}

output "db_name" {
  description = "Database name"
  value       = aws_db_instance.this.db_name
}

output "db_master_username" {
  description = "RDS master username"
  value       = aws_db_instance.this.username
}

output "db_subnet_group_name" {
  description = "RDS subnet group name"
  value       = aws_db_subnet_group.this.name
}

output "master_user_secret_arn" {
  description = "AWS-managed Secrets Manager ARN for the RDS master user password"
  value       = try(aws_db_instance.this.master_user_secret[0].secret_arn, null)
  sensitive   = true
}

output "backup_retention_period" {
  description = "RDS automated backup retention period in days"
  value       = aws_db_instance.this.backup_retention_period
}

output "backup_window" {
  description = "RDS preferred backup window"
  value       = aws_db_instance.this.backup_window
}

output "maintenance_window" {
  description = "RDS preferred maintenance window"
  value       = aws_db_instance.this.maintenance_window
}

output "deletion_protection" {
  description = "Whether deletion protection is enabled for the RDS instance"
  value       = aws_db_instance.this.deletion_protection
}

output "skip_final_snapshot" {
  description = "Whether final snapshot is skipped during RDS destroy"
  value       = aws_db_instance.this.skip_final_snapshot
}

output "copy_tags_to_snapshot" {
  description = "Whether RDS tags are copied to snapshots"
  value       = aws_db_instance.this.copy_tags_to_snapshot
}
