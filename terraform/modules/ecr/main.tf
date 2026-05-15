locals {
  environment_prefix = "${var.project}-${var.environment}"
}

resource "aws_ecr_repository" "service" {
  for_each = toset(var.service_names)

  # Platform-aligned naming:
  # petclinic-dev/config-server
  # petclinic-dev/discovery-server
  # petclinic-dev/api-gateway
  name = "${local.environment_prefix}/${each.value}"

  force_delete         = true
  image_tag_mutability = var.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name    = "${local.environment_prefix}/${each.value}"
    Service = each.value
  }
}

resource "aws_ecr_lifecycle_policy" "service" {
  for_each = aws_ecr_repository.service

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after ${var.untagged_image_retention_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_image_retention_days
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Keep only the latest ${var.tagged_image_retention_count} tagged commit/version images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["sha-", "commit-", "v"]
          countType     = "imageCountMoreThan"
          countNumber   = var.tagged_image_retention_count
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
