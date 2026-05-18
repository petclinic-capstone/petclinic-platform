data "aws_caller_identity" "current" {}

# ── VPC ───────────────────────────────────────────────────────────────────────
module "vpc" {
  source = "../../modules/vpc"

  project      = var.project
  environment  = var.environment
  cluster_name = "${var.project}-${var.environment}"

  vpc_cidr = "10.0.0.0/16"

  availability_zones  = ["us-east-1a", "us-east-1b"]
  public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
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

  node_instance_types = ["t4g.medium"]
  node_ami_type       = "AL2023_ARM_64_STANDARD"
  node_capacity_type  = "ON_DEMAND"
  node_disk_size      = 20

  node_desired_size = 2
  node_min_size     = 2
  node_max_size     = 4
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

  image_tag_mutability          = "MUTABLE"
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
  multi_az                = false
  backup_retention_period = 7
  deletion_protection     = false
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

# ── Observability (CloudWatch) ────────────────────────────────────────────────
module "observability" {
  source = "../../modules/observability"

  project      = var.project
  environment  = var.environment
  aws_region   = var.aws_region
  cluster_name = module.eks.cluster_name

  log_retention_days      = 30
  billing_alert_threshold = 50
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

# ── Cost Control Lambda ───────────────────────────────────────────────────────
module "cost_control" {
  source = "../../modules/cost-control"

  project        = var.project
  environment    = var.environment
  aws_region     = var.aws_region
  aws_account_id = data.aws_caller_identity.current.account_id

  rds_identifier     = module.rds.db_instance_identifier
  eks_cluster_name   = module.eks.cluster_name
  eks_nodegroup_name = module.eks.node_group_name

  node_min = 2
  node_max = 4
}
