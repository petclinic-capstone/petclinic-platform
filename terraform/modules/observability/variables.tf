variable "project"      { type = string }
variable "environment"  { type = string }
variable "cluster_name" { type = string }

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "log_retention_days" {
  description = "Days to retain CloudWatch logs"
  type        = number
  default     = 30
}

variable "billing_alert_threshold" {
  description = "USD amount that triggers a billing alarm"
  type        = number
  default     = 50
}

variable "alarm_sns_arn" {
  description = "SNS topic ARN for billing alarm notifications (leave empty to skip)"
  type        = string
  default     = ""
}
