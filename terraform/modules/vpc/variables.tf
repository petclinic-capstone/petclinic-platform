variable "project" {
  description = "Project name used for tagging and naming"
  type        = string
}

variable "environment" {
  description = "Environment name such as dev, staging, or prod"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the PetClinic VPC"
  type        = string
}

variable "availability_zones" {
  description = "Availability zones for public subnets"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
}

variable "cluster_name" {
  description = "EKS cluster name used for Kubernetes subnet discovery tags"
  type        = string
}

variable "region" {
  description = "AWS region — used by the pre-destroy cleanup script"
  type        = string
  default     = "us-east-1"
}
