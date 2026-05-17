# =============================================================================
# terraform/environments/prod/main.tf
#
# Production environment — built but NOT deployed until demo day sign-off.
#
# Key differences from dev:
#   VPC       : 10.1.0.0/16  (dev uses 10.0.0.0/16 — no CIDR overlap)
#   ECR       : IMMUTABLE tags (dev uses MUTABLE)
#   RDS       : deletion_protection=true, multi_az=false*, secret recovery 7d
#   CloudWatch: 90-day log retention (dev uses 30d)
#   Billing   : alarm at $100/day (dev alarms at $50)
#   Cost ctrl : NO auto-destroy Lambda (prod stays up until explicit destroy)
#
#   * multi_az=false keeps capstone costs manageable. Flip to true for real
#     production workloads before demo day if the team decides to.
# =============================================================================

data "aws_caller_identity" "current" {}

# ── VPC ───────────────────────────────────────────────────────────────────────
module "vpc" {
  source = "../../modules/vpc"

  project      = var.project
  environment  = var.environment
  cluster_name = "${var.project}-${var.environment}"
  region       = var.aws_region

  # 10.1.x.x range — no overlap with dev (10.0.x.x)
  vpc_cidr = "10.1.0.0/16"

  availability_zones = ["us-east-1a", "us-east-1b"]

  public_subnet_cidrs = ["10.1.1.0/24", "10.1.2.0/24"]
}

# ── EKS ───────────────────────────────────────────────────────────────────────
module "eks" {
  source = "../../modules/eks"

  project      = var.project
  environment  = var.environment
  cluster_name = "${var.project}-${var.environment}"

  cluster_version = "1.33"

  subnet_ids                = module.vpc.public_subnet_ids
  cluster_security_group_id = module.vpc.eks_cluster_security_group_id
  node_security_group_id    = module.vpc.eks_node_security_group_id

  # Same hardware tier as dev — capstone budget constraint
  node_instance_types = ["t4g.small"]
  node_ami_type       = "AL2023_ARM_64_STANDARD"
  node_capacity_type  = "ON_DEMAND"
  node_disk_size      = 20

  node_desired_size = 2
  node_min_size     = 2
  node_max_size     = 4

  log_retention_days = 90   # Prod: 90d vs dev: 30d

  ebs_csi_role_arn = module.iam.ebs_csi_role_arn
}

# ── ECR ───────────────────────────────────────────────────────────────────────
module "ecr" {
  source = "../../modules/ecr"

  project     = var.project
  environment = var.environment

  service_names = [
    "config-server",
    "discovery-server",
    "api-gateway",
    "customers-service",
    "visits-service",
    "vets-service",
    "genai-service",
    "admin-server",
  ]

  # IMMUTABLE in prod — prevents overwriting tagged releases
  image_tag_mutability          = "IMMUTABLE"
  scan_on_push                  = true
  untagged_image_retention_days = 7
  tagged_image_retention_count  = 10
}

# ── RDS ───────────────────────────────────────────────────────────────────────
module "rds" {
  source = "../../modules/rds"

  project     = var.project
  environment = var.environment

  subnet_ids         = module.vpc.public_subnet_ids
  security_group_ids = [module.vpc.rds_security_group_id]

  database_name   = "petclinic"
  master_username = "petclinic"

  instance_class          = "db.t4g.micro"
  allocated_storage       = 20
  multi_az                = false   # Set true for HA before real prod launch
  backup_retention_period = 7
  deletion_protection     = true    # Prod: prevents accidental terraform destroy

  # 7-day secret recovery window in prod — allows accidental delete recovery
  secret_recovery_window_days = 7
}

# ── IAM ───────────────────────────────────────────────────────────────────────
module "iam" {
  source = "../../modules/iam"

  project        = var.project
  environment    = var.environment
  aws_account_id = data.aws_caller_identity.current.account_id
  aws_region     = var.aws_region

  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url

  rds_secret_arn = module.rds.master_user_secret_arn

  github_org      = var.github_org
  github_repo     = var.github_repo
  github_branch   = var.github_branch
  github_tf_repos = var.github_tf_repos
}

# ── CloudWatch ────────────────────────────────────────────────────────────────
module "cloudwatch" {
  source = "../../modules/cloudwatch"

  project      = var.project
  environment  = var.environment
  aws_region   = var.aws_region
  cluster_name = module.eks.cluster_name

  log_retention_days      = 90    # Prod: 90d vs dev: 30d
  billing_alert_threshold = 100   # Alert when estimated charges exceed $100/day
}

# ── DNS / Route53 ─────────────────────────────────────────────────────────────
module "dns" {
  source = "../../modules/dns"

  project     = var.project
  environment = var.environment

  domain_name = var.domain_name

  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
}

# ── Cost Control ──────────────────────────────────────────────────────────────
# NOTE: No cost-control Lambda in prod.
# Prod infrastructure runs continuously until an explicit terraform destroy.
# Use the AWS console or billing alarms to monitor spend.
# To tear down prod: run terraform destroy from this directory manually after
# disabling deletion_protection on the RDS instance first:
#   aws rds modify-db-instance --db-instance-identifier petclinic-prod-mysql \
#     --no-deletion-protection --apply-immediately
