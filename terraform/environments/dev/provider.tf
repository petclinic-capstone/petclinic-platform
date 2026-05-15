provider "aws" {
  region  = var.aws_region
  profile = "petclinic-infra-paul"

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      Team        = "team-1-infra"
      ManagedBy   = "terraform"
    }
  }
}
