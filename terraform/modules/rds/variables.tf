variable "project" {
  description = "Project name used for naming and tagging"
  type        = string
}

variable "environment" {
  description = "Environment name such as dev or prod"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs used by the RDS DB subnet group"
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security group IDs attached to the RDS instance"
  type        = list(string)
}

variable "database_name" {
  description = "Initial database name for PetClinic"
  type        = string
  default     = "petclinic"
}

variable "master_username" {
  description = "Master username for the RDS instance"
  type        = string
  default     = "petclinicadmin"
}

variable "engine" {
  description = "RDS database engine"
  type        = string
  default     = "mysql"
}

variable "instance_class" {
  description = "RDS instance class for dev environment"
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage" {
  description = "Allocated storage in GB"
  type        = number
  default     = 20
}

variable "storage_type" {
  description = "RDS storage type"
  type        = string
  default     = "gp3"
}

variable "multi_az" {
  description = "Whether to enable Multi-AZ for RDS"
  type        = bool
  default     = false
}

variable "publicly_accessible" {
  description = "Whether the RDS instance should be publicly accessible"
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "Backup retention period in days for RDS automated backups"
  type        = number
  default     = 1
}

variable "backup_window" {
  description = "Preferred daily backup window for RDS automated backups"
  type        = string
  default     = "03:00-04:00"
}

variable "maintenance_window" {
  description = "Preferred weekly maintenance window for the RDS instance"
  type        = string
  default     = "sun:04:00-sun:05:00"
}

variable "deletion_protection" {
  description = "Whether deletion protection is enabled"
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Whether to skip final snapshot when destroying the RDS instance"
  type        = bool
  default     = false
}

variable "final_snapshot_identifier" {
  description = "Final snapshot identifier used when skip_final_snapshot is false"
  type        = string
  default     = null
}

variable "copy_tags_to_snapshot" {
  description = "Whether to copy DB instance tags to snapshots"
  type        = bool
  default     = true
}
