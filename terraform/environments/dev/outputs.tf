
output "aws_account_id" {
  description = "AWS account used by the dev environment"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS region used by the dev environment"
  value       = var.aws_region
}

# ── IAM role ARNs ─────────────────────────────────────────────────────────────

output "iam_github_actions_role_arn" {
  description = "OIDC role ARN for app CI (ECR push) — set as AWS_ROLE_ARN in spring-petclinic-microservices repo secrets"
  value       = module.iam.github_actions_role_arn
}

output "iam_github_actions_tf_role_arn" {
  description = "OIDC role ARN for platform CI (Terraform plan/apply) — set as TF_ROLE_ARN in petclinic-platform repo secrets"
  value       = module.iam.github_actions_tf_role_arn
}

output "iam_lb_controller_role_arn" {
  description = "IRSA role ARN for AWS Load Balancer Controller — paste into kubernetes/base/aws-load-balancer-controller/helm-values.yaml"
  value       = module.iam.lb_controller_role_arn
}

output "iam_eso_role_arn" {
  description = "IRSA role ARN for External Secrets Operator — injected at ESO helm install via --set serviceAccount.annotations"
  value       = module.iam.eso_role_arn
}

output "iam_ebs_csi_role_arn" {
  description = "IRSA role ARN for EBS CSI Driver — applied to ebs-csi-controller-sa ServiceAccount"
  value       = module.iam.ebs_csi_role_arn
}

output "karpenter_node_role_arn" {
  description = "Karpenter node role ARN — add to EKS aws-auth ConfigMap or access entry"
  value       = module.iam.karpenter_node_role_arn
}

output "karpenter_node_instance_profile_arn" {
  description = "Karpenter node instance profile ARN — set in EC2NodeClass spec"
  value       = module.iam.karpenter_node_instance_profile_arn
}

output "karpenter_controller_role_arn" {
  description = "IRSA role ARN for Karpenter controller — annotate karpenter ServiceAccount with this"
  value       = module.iam.karpenter_controller_role_arn
}

# ── VPC ───────────────────────────────────────────────────────────────────────

output "vpc_id" {
  description = "PetClinic dev VPC ID"
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "PetClinic dev VPC CIDR"
  value       = module.vpc.vpc_cidr
}

output "public_subnet_ids" {
  description = "Public subnet IDs for EKS and ALB"
  value       = module.vpc.public_subnet_ids
}

output "public_subnet_cidrs" {
  description = "Public subnet CIDR blocks"
  value       = module.vpc.public_subnet_cidrs
}

output "internet_gateway_id" {
  description = "Internet Gateway ID"
  value       = module.vpc.internet_gateway_id
}

output "public_route_table_id" {
  description = "Public route table ID"
  value       = module.vpc.public_route_table_id
}

output "eks_cluster_security_group_id" {
  description = "EKS cluster security group ID"
  value       = module.vpc.eks_cluster_security_group_id
}

output "eks_node_security_group_id" {
  description = "EKS worker node security group ID"
  value       = module.vpc.eks_node_security_group_id
}

output "rds_security_group_id" {
  description = "RDS MySQL security group ID"
  value       = module.vpc.rds_security_group_id
}

output "alb_security_group_id" {
  description = "Public ALB security group ID"
  value       = module.vpc.alb_security_group_id
}

# ── EKS ───────────────────────────────────────────────────────────────────────

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_certificate_authority_data" {
  description = "EKS cluster certificate authority data"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "eks_node_group_name" {
  description = "EKS managed node group name"
  value       = module.eks.node_group_name
}

output "eks_node_role_arn" {
  description = "EKS node IAM role ARN"
  value       = module.eks.node_role_arn
}

output "eks_cluster_role_arn" {
  description = "EKS cluster IAM role ARN"
  value       = module.eks.cluster_role_arn
}

output "eks_oidc_provider_arn" {
  description = "EKS OIDC provider ARN"
  value       = module.eks.oidc_provider_arn
}

output "eks_oidc_provider_url" {
  description = "EKS OIDC provider URL"
  value       = module.eks.oidc_provider_url
}

# ── ECR ───────────────────────────────────────────────────────────────────────

output "ecr_repository_names" {
  description = "ECR repository names by service"
  value       = module.ecr.repository_names
}

output "ecr_repository_urls" {
  description = "ECR repository URLs by service"
  value       = module.ecr.repository_urls
}

output "ecr_repository_arns" {
  description = "ECR repository ARNs by service"
  value       = module.ecr.repository_arns
}

output "ecr_environment_prefix" {
  description = "ECR environment prefix used by platform CI/CD"
  value       = module.ecr.environment_prefix
}

# ── RDS ───────────────────────────────────────────────────────────────────────

output "rds_endpoint" {
  description = "RDS MySQL endpoint hostname"
  value       = module.rds.db_endpoint
}

output "rds_port" {
  description = "RDS MySQL port"
  value       = module.rds.db_port
}

output "rds_database_name" {
  description = "MySQL database name"
  value       = module.rds.db_name
}

output "rds_master_username" {
  description = "RDS master username"
  value       = module.rds.db_master_username
}

output "rds_secret_arn" {
  description = "AWS Secrets Manager ARN for RDS credentials — paste into kubernetes/base/external-secrets/externalsecret-db.yaml"
  value       = module.rds.master_user_secret_arn
  sensitive   = true
}

output "rds_backup_retention_period" {
  description = "RDS automated backup retention period in days"
  value       = module.rds.backup_retention_period
}

output "rds_backup_window" {
  description = "RDS preferred backup window"
  value       = module.rds.backup_window
}

output "rds_maintenance_window" {
  description = "RDS preferred maintenance window"
  value       = module.rds.maintenance_window
}

output "rds_deletion_protection" {
  description = "Whether deletion protection is enabled for RDS"
  value       = module.rds.deletion_protection
}

output "rds_skip_final_snapshot" {
  description = "Whether RDS final snapshot is skipped on destroy"
  value       = module.rds.skip_final_snapshot
}

output "rds_copy_tags_to_snapshot" {
  description = "Whether RDS tags are copied to snapshots"
  value       = module.rds.copy_tags_to_snapshot
}
