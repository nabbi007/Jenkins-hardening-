variable "project_name" {
  description = "Project name for resource naming and tags"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where Jenkins instance will run"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for Jenkins instance"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for Jenkins host"
  type        = string
  default     = "t3.large"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GiB"
  type        = number
  default     = 40
}

variable "key_name" {
  description = "Optional EC2 key pair name"
  type        = string
  default     = null
}

variable "allowed_cidrs" {
  description = "CIDRs allowed to reach Jenkins host"
  type        = list(string)
}

variable "ingress_ports" {
  description = "Ports opened on Jenkins security group"
  type        = list(number)
  default     = [22, 8080, 9000]
}

variable "associate_public_ip_address" {
  description = "Associate public IP to Jenkins instance"
  type        = bool
  default     = true
}

variable "ecr_repository_arns" {
  description = "ECR repository ARNs Jenkins should push images to"
  type        = list(string)
}

variable "ecs_task_role_arns" {
  description = "IAM role ARNs Jenkins is allowed to pass to ECS"
  type        = list(string)
}
