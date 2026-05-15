variable "project" {
  description = "Project name — used in role naming"
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Deployment environment (dev or prod)"
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be 'dev' or 'prod'."
  }
}

variable "aws_account_id" {
  description = "AWS account ID — passed from data.aws_caller_identity in the environment root"
  type        = string
}

variable "aws_region" {
  description = "AWS region where resources live"
  type        = string
  default     = "us-east-1"
}

# ---------------------------------------------------------------------------
# EKS OIDC — values come from module.eks outputs
# ---------------------------------------------------------------------------

variable "oidc_provider_arn" {
  description = "EKS OIDC provider ARN (module.eks.oidc_provider_arn)"
  type        = string
}

variable "oidc_provider_url" {
  description = "EKS OIDC provider URL including https:// prefix (module.eks.oidc_provider_url) — the module strips the prefix internally"
  type        = string
}

# ---------------------------------------------------------------------------
# RDS secret — passed from module.rds.master_user_secret_arn
# Required so ESO gets the exact Secrets Manager ARN to read
# ---------------------------------------------------------------------------

variable "rds_secret_arn" {
  description = "Secrets Manager ARN of the AWS-managed RDS master user password (module.rds.master_user_secret_arn)"
  type        = string
  sensitive   = true
}

# ---------------------------------------------------------------------------
# GitHub Actions OIDC — scopes the CI role to the repos that need AWS access
#
# TWO repos must be listed:
#   1. spring-petclinic-microservices — runs build-push.yml (ECR push)
#   2. petclinic-platform             — runs terraform-ci.yml (Terraform apply)
#
# The trust policy grants all listed repos the StringLike condition,
# so each can independently assume this role via OIDC.
# ---------------------------------------------------------------------------

variable "github_org" {
  description = "GitHub organisation that owns the CI repositories. Note: IAM trust policies use full 'org/repo' paths from github_repo and github_tf_repos — this variable is not used in trust conditions but kept for naming/tagging reference."
  type        = string
}

variable "github_repo" {
  description = "List of GitHub repositories in 'org/repo' format allowed to assume the CI role. Supports repos from different organisations."
  type        = list(string)
}

variable "github_branch" {
  description = "Primary branch name (informational). IAM trust uses 'repo:org/repo:*' to allow both push and PR workflows. Branch-level enforcement is handled by workflow conditions, not IAM."
  type        = string
  default     = "main"
}

variable "github_tf_repos" {
  description = "List of GitHub repositories in 'org/repo' format allowed to assume the Terraform CI role — typically the platform repo only"
  type        = list(string)
}
