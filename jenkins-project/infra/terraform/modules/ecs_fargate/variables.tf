variable "project_name" {
  description = "Project name for tags"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "cluster_name" {
  description = "ECS cluster name"
  type        = string
}

variable "service_name" {
  description = "ECS service name"
  type        = string
}

variable "task_family" {
  description = "Task definition family"
  type        = string
}

variable "desired_count" {
  description = "ECS desired task count"
  type        = number
}

variable "assign_public_ip" {
  description = "Assign public IP to tasks"
  type        = bool
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs"
  type        = list(string)
}

variable "allowed_ingress_cidrs" {
  description = "CIDRs allowed to hit frontend container"
  type        = list(string)
}

variable "public_ingress_ports" {
  description = "Public ports opened on ECS service security group"
  type        = list(number)
}

variable "task_cpu" {
  description = "Fargate task CPU"
  type        = number
}

variable "task_memory" {
  description = "Fargate task memory"
  type        = number
}

variable "backend_container_name" {
  description = "Backend container name"
  type        = string
}

variable "frontend_container_name" {
  description = "Frontend container name"
  type        = string
}

variable "backend_image_uri" {
  description = "Backend image URI"
  type        = string
}

variable "frontend_image_uri" {
  description = "Frontend image URI"
  type        = string
}

variable "backend_container_cpu" {
  description = "Backend container CPU"
  type        = number
}

variable "backend_container_memory" {
  description = "Backend container memory"
  type        = number
}

variable "frontend_container_cpu" {
  description = "Frontend container CPU"
  type        = number
}

variable "frontend_container_memory" {
  description = "Frontend container memory"
  type        = number
}

variable "backend_container_port" {
  description = "Backend container port"
  type        = number
}

variable "frontend_container_port" {
  description = "Frontend container port"
  type        = number
}

variable "backend_log_group_name" {
  description = "Backend CloudWatch log group"
  type        = string
}

variable "frontend_log_group_name" {
  description = "Frontend CloudWatch log group"
  type        = string
}

variable "execution_role_arn" {
  description = "Existing execution role ARN"
  type        = string
  default     = null
}

variable "task_role_arn" {
  description = "Existing task role ARN"
  type        = string
  default     = null
}
