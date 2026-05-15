data "aws_caller_identity" "current" {}

module "vpc" {
  source = "../../modules/vpc"

  project      = var.project
  environment  = var.environment
  cluster_name = "${var.project}-${var.environment}"

  vpc_cidr = "10.0.0.0/16"

  availability_zones = [
    "us-east-1a",
    "us-east-1b"
  ]

  public_subnet_cidrs = [
    "10.0.1.0/24",
    "10.0.2.0/24"
  ]
}

module "eks" {
  source = "../../modules/eks"

  project      = var.project
  environment  = var.environment
  cluster_name = "${var.project}-${var.environment}"

  cluster_version = "1.33"

  subnet_ids = module.vpc.public_subnet_ids

  cluster_security_group_id = module.vpc.eks_cluster_security_group_id
  node_security_group_id    = module.vpc.eks_node_security_group_id

  node_instance_types = ["t4g.small"]
  node_ami_type       = "AL2023_ARM_64_STANDARD"
  node_capacity_type  = "ON_DEMAND"
  node_disk_size      = 20

  node_desired_size = 2
  node_min_size     = 2
  node_max_size     = 4
}

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
    "admin-server"
  ]

  image_tag_mutability          = "MUTABLE"
  scan_on_push                  = true
  untagged_image_retention_days = 7
  tagged_image_retention_count  = 20
}

module "rds" {
  source = "../../modules/rds"

  project     = var.project
  environment = var.environment

  subnet_ids = module.vpc.public_subnet_ids

  security_group_ids = [
    module.vpc.rds_security_group_id
  ]

  database_name   = "petclinic"
  master_username = "petclinicadmin"

  instance_class      = "db.t4g.micro"
  allocated_storage   = 20
  storage_type        = "gp3"
  publicly_accessible = false
  multi_az            = false

  backup_retention_period = 0
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  deletion_protection       = false
  skip_final_snapshot       = true
  final_snapshot_identifier = "${var.project}-${var.environment}-rds-final-snapshot"
  copy_tags_to_snapshot     = true
}

module "iam" {
  source = "../../modules/iam"

  project        = var.project
  environment    = var.environment
  aws_account_id = data.aws_caller_identity.current.account_id
  aws_region     = var.aws_region

  # OIDC values from the EKS module — do not hardcode these
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url

  # RDS secret ARN — the exact Secrets Manager secret ESO is allowed to read
  rds_secret_arn = module.rds.master_user_secret_arn

  # App CI repos — trusted to push Docker images to ECR (AWS_ROLE_ARN secret)
  github_org    = var.github_org
  github_repo   = var.github_repo
  github_branch = var.github_branch

  # Platform CI repos — trusted to run terraform plan/apply (TF_ROLE_ARN secret)
  github_tf_repos = var.github_tf_repos
}
