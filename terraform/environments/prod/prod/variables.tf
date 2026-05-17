variable "aws_region" {
  description = "AWS region for the PetClinic platform"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name"
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

variable "github_org" {
  description = "GitHub organisation or user name that owns the application repository"
  type        = string
}

variable "github_repo" {
  description = "List of GitHub repositories in 'org/repo' format allowed to assume the CI role"
  type        = list(string)
}

variable "github_branch" {
  description = "Branch allowed to assume the GitHub Actions CI role"
  type        = string
  default     = "main"
}

variable "github_tf_repos" {
  description = "List of GitHub repositories in 'org/repo' format allowed to assume the Terraform CI role"
  type        = list(string)
}

variable "domain_name" {
  description = "Domain name for the Route53 hosted zone — must already exist"
  type        = string
}
