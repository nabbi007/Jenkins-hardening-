output "instance_id" {
  description = "Jenkins EC2 instance ID"
  value       = aws_instance.jenkins.id
}

output "public_ip" {
  description = "Jenkins public IP"
  value       = aws_instance.jenkins.public_ip
}

output "public_dns" {
  description = "Jenkins public DNS"
  value       = aws_instance.jenkins.public_dns
}

output "private_ip" {
  description = "Jenkins private IP"
  value       = aws_instance.jenkins.private_ip
}

output "security_group_id" {
  description = "Jenkins security group ID"
  value       = aws_security_group.jenkins.id
}

output "instance_profile_name" {
  description = "Jenkins instance profile name"
  value       = aws_iam_instance_profile.jenkins.name
}

output "role_arn" {
  description = "Jenkins IAM role ARN"
  value       = aws_iam_role.jenkins.arn
}

output "secrets_manager_secret_arn" {
  description = "ARN of the Secrets Manager secret containing ECS role ARNs"
  value       = aws_secretsmanager_secret.jenkins_ecs_roles.arn
}

output "secrets_manager_secret_name" {
  description = "Name of the Secrets Manager secret"
  value       = aws_secretsmanager_secret.jenkins_ecs_roles.name
}
