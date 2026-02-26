output "ecr_repository_urls" {
  description = "ECR repository URLs"
  value       = module.ecr.repository_urls
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = module.ecs_fargate.cluster_name
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = module.ecs_fargate.service_name
}

output "ecs_task_family" {
  description = "ECS task definition family"
  value       = module.ecs_fargate.task_family
}

output "ecs_task_execution_role_arn" {
  description = "Task execution role ARN"
  value       = module.ecs_fargate.execution_role_arn
}

output "ecs_task_role_arn" {
  description = "Task role ARN"
  value       = module.ecs_fargate.task_role_arn
}

output "ecs_security_group_id" {
  description = "Security group attached to ECS service"
  value       = module.ecs_fargate.security_group_id
}

output "alb_dns_name" {
  description = "Application Load Balancer DNS name for app access"
  value       = module.ecs_fargate.alb_dns_name
}

output "alb_zone_id" {
  description = "Application Load Balancer Route53 zone ID"
  value       = module.ecs_fargate.alb_zone_id
}

output "app_url" {
  description = "Application URL for ALB entrypoint (HTTPS when certificate is configured, otherwise HTTP)"
  value       = module.ecs_fargate.alb_dns_name != null ? format("%s://%s", trim(coalesce(var.alb_certificate_arn, "")) != "" ? "https" : "http", module.ecs_fargate.alb_dns_name) : null
}

output "jenkins_instance_id" {
  description = "Jenkins EC2 instance ID"
  value       = var.create_jenkins_instance ? module.jenkins_ec2[0].instance_id : null
}

output "jenkins_public_ip" {
  description = "Jenkins EC2 public IP"
  value       = var.create_jenkins_instance ? module.jenkins_ec2[0].public_ip : null
}

output "jenkins_public_dns" {
  description = "Jenkins EC2 public DNS"
  value       = var.create_jenkins_instance ? module.jenkins_ec2[0].public_dns : null
}

output "jenkins_security_group_id" {
  description = "Security group ID for Jenkins instance"
  value       = var.create_jenkins_instance ? module.jenkins_ec2[0].security_group_id : null
}
