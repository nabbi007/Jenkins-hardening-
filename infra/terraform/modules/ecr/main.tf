locals {
  repository_set = toset(var.repositories)
}

resource "aws_ecr_repository" "this" {
  for_each = var.create_repositories ? local.repository_set : toset([])

  name                 = each.value
  image_tag_mutability = var.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Project = var.project_name
  }
}

data "aws_ecr_repository" "existing" {
  for_each = var.create_repositories ? toset([]) : local.repository_set

  name = each.value
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each = local.repository_set

  repository = each.value
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep latest ${var.lifecycle_keep_images} images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.lifecycle_keep_images
        }
        action = {
          type = "expire"
        }
      }
    ]
  })

  depends_on = [aws_ecr_repository.this]
}
