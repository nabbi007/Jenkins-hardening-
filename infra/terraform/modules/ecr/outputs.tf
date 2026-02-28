output "repository_urls" {
  description = "Map of repository name => repository URL"
  value       = var.create_repositories ? { for k, repo in aws_ecr_repository.this : k => repo.repository_url } : { for k, repo in data.aws_ecr_repository.existing : k => repo.repository_url }
}

output "repository_arns" {
  description = "Map of repository name => repository ARN"
  value       = var.create_repositories ? { for k, repo in aws_ecr_repository.this : k => repo.arn } : { for k, repo in data.aws_ecr_repository.existing : k => repo.arn }
}
