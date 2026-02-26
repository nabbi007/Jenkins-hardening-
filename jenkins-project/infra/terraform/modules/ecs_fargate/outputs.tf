output "cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.this.name
}

output "cluster_arn" {
  description = "ECS cluster ARN"
  value       = aws_ecs_cluster.this.arn
}

output "service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.this.name
}

output "service_arn" {
  description = "ECS service ARN"
  value       = aws_ecs_service.this.id
}

output "task_family" {
  description = "Task definition family"
  value       = aws_ecs_task_definition.this.family
}

output "security_group_id" {
  description = "ECS service security group ID"
  value       = aws_security_group.ecs_service.id
}

output "execution_role_arn" {
  description = "Task execution role ARN"
  value       = local.execution_role_arn
}

output "task_role_arn" {
  description = "Task role ARN"
  value       = local.task_role_arn
}

output "backend_log_group_name" {
  description = "Backend log group"
  value       = aws_cloudwatch_log_group.backend.name
}

output "frontend_log_group_name" {
  description = "Frontend log group"
  value       = aws_cloudwatch_log_group.frontend.name
}
