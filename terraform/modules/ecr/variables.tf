variable "project" {
  description = "Project name used for naming and tagging"
  type        = string
}

variable "environment" {
  description = "Environment name such as dev or prod"
  type        = string
}

variable "service_names" {
  description = "List of PetClinic service names requiring ECR repositories"
  type        = list(string)
}

variable "image_tag_mutability" {
  description = "Image tag mutability setting for ECR repositories"
  type        = string
  default     = "MUTABLE"
}

variable "scan_on_push" {
  description = "Enable image scan on push"
  type        = bool
  default     = true
}

variable "untagged_image_retention_days" {
  description = "Number of days to retain untagged images"
  type        = number
  default     = 7
}

variable "tagged_image_retention_count" {
  description = "Number of tagged images to retain per repository"
  type        = number
  default     = 20
}
