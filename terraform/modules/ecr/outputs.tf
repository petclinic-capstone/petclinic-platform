output "repository_names" {
  description = "ECR repository names by service"
  value       = { for service, repo in aws_ecr_repository.service : service => repo.name }
}

output "repository_urls" {
  description = "ECR repository URLs by service"
  value       = { for service, repo in aws_ecr_repository.service : service => repo.repository_url }
}

output "repository_arns" {
  description = "ECR repository ARNs by service"
  value       = { for service, repo in aws_ecr_repository.service : service => repo.arn }
}

output "repository_registry_ids" {
  description = "Registry IDs for ECR repositories by service"
  value       = { for service, repo in aws_ecr_repository.service : service => repo.registry_id }
}

output "environment_prefix" {
  description = "Environment-level ECR prefix, for example petclinic-dev"
  value       = local.environment_prefix
}
