variable "project" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

variable "rds_identifier" {
  description = "RDS DB instance identifier to control (e.g. petclinic-dev-mysql)"
  type        = string
}

variable "eks_cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "eks_nodegroup_name" {
  description = "EKS managed node group name"
  type        = string
}

variable "node_min" {
  description = "Minimum node count when cluster is running (used when starting resources)"
  type        = number
  default     = 2
}

variable "node_max" {
  description = "Maximum node count allowed"
  type        = number
  default     = 4
}
