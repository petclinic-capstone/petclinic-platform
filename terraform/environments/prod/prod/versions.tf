terraform {
  required_version = ">= 1.6.0"

  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }

    # Required by the cost-control module (archive_file data source)
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }

    # Required by the VPC module pre-destroy cleanup (null_resource)
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }

    # Required by the RDS module (random_password for master credentials)
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}
