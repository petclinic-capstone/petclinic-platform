variable "project"      { type = string }
variable "environment"  { type = string }

variable "domain_name" {
  description = "Root domain for the existing Route53 hosted zone (e.g. demo.lulamistack.com)"
  type        = string
}

variable "oidc_provider_arn" {
  description = "EKS OIDC provider ARN"
  type        = string
}

variable "oidc_provider_url" {
  description = "EKS OIDC provider URL including https:// prefix"
  type        = string
}
