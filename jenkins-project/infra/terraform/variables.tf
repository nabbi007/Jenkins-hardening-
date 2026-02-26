variable "aws_region" {
  description = "AWS region for ECR/ECS resources"
  type        = string
  default     = "eu-west-1"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "voting-app"
}

variable "vpc_id" {
  description = "Existing VPC ID. If null, default VPC is used"
  type        = string
  default     = null
}

variable "subnet_ids" {
  description = "Subnet IDs used by ECS service. If empty, all subnets in selected VPC are used"
  type        = list(string)
  default     = []
}

variable "allowed_ingress_cidrs" {
  description = "CIDRs allowed to reach frontend service port"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "ecs_public_ingress_ports" {
  description = "Ports exposed publicly on the ECS service security group"
  type        = list(number)
  default     = [80, 3000]
}

variable "backend_ecr_repo_name" {
  description = "ECR repo name for backend image"
  type        = string
  default     = "backend-service"
}

variable "frontend_ecr_repo_name" {
  description = "ECR repo name for frontend image"
  type        = string
  default     = "frontend-web"
}

variable "ecr_lifecycle_keep_images" {
  description = "Keep last N images in ECR"
  type        = number
  default     = 30
}

variable "ecs_cluster_name" {
  description = "ECS cluster name"
  type        = string
  default     = "voting-cluster"
}

variable "ecs_service_name" {
  description = "ECS service name"
  type        = string
  default     = "voting-app"
}

variable "ecs_task_family" {
  description = "ECS task definition family"
  type        = string
  default     = "voting-app"
}

variable "desired_count" {
  description = "Desired ECS task count"
  type        = number
  default     = 1
}

variable "assign_public_ip" {
  description = "Assign public IP to ECS tasks"
  type        = bool
  default     = true
}

variable "task_cpu" {
  description = "Fargate task CPU"
  type        = number
  default     = 512
}

variable "task_memory" {
  description = "Fargate task memory"
  type        = number
  default     = 1024
}

variable "backend_container_cpu" {
  description = "Backend container CPU"
  type        = number
  default     = 256
}

variable "backend_container_memory" {
  description = "Backend container memory"
  type        = number
  default     = 512
}

variable "frontend_container_cpu" {
  description = "Frontend container CPU"
  type        = number
  default     = 256
}

variable "frontend_container_memory" {
  description = "Frontend container memory"
  type        = number
  default     = 512
}

variable "backend_container_port" {
  description = "Backend container port"
  type        = number
  default     = 3000
}

variable "frontend_container_port" {
  description = "Frontend container port"
  type        = number
  default     = 80
}

variable "backend_log_group_name" {
  description = "CloudWatch log group for backend container"
  type        = string
  default     = "/ecs/voting-app/backend"
}

variable "frontend_log_group_name" {
  description = "CloudWatch log group for frontend container"
  type        = string
  default     = "/ecs/voting-app/frontend"
}

variable "backend_image_tag" {
  description = "Initial backend image tag used by Terraform deployment"
  type        = string
  default     = "latest"
}

variable "frontend_image_tag" {
  description = "Initial frontend image tag used by Terraform deployment"
  type        = string
  default     = "latest"
}

variable "execution_role_arn" {
  description = "Optional existing task execution role ARN"
  type        = string
  default     = null
}

variable "task_role_arn" {
  description = "Optional existing task role ARN"
  type        = string
  default     = null
}

variable "alarm_sns_topic_arn" {
  description = "Optional SNS topic ARN for CloudWatch alarms"
  type        = string
  default     = null
}

variable "cpu_alarm_threshold" {
  description = "ECS service CPU alarm threshold"
  type        = number
  default     = 80
}

variable "memory_alarm_threshold" {
  description = "ECS service memory alarm threshold"
  type        = number
  default     = 80
}

variable "create_jenkins_instance" {
  description = "Create a Jenkins EC2 instance with bootstrap user data"
  type        = bool
  default     = true
}

variable "jenkins_subnet_id" {
  description = "Subnet ID for Jenkins instance. If null, the first selected subnet is used"
  type        = string
  default     = null
}

variable "jenkins_allowed_cidrs" {
  description = "CIDRs allowed to access Jenkins (8080) and SSH (22). If empty, allowed_ingress_cidrs is used"
  type        = list(string)
  default     = []
}

variable "jenkins_ingress_ports" {
  description = "Ports opened publicly for Jenkins host"
  type        = list(number)
  default     = [22, 8080, 9000]
}

variable "jenkins_instance_type" {
  description = "EC2 instance type for Jenkins server"
  type        = string
  default     = "t3.large"
}

variable "jenkins_root_volume_size" {
  description = "Root volume size (GiB) for Jenkins server"
  type        = number
  default     = 40
}

variable "jenkins_key_name" {
  description = "Optional key pair name for SSH access to Jenkins instance"
  type        = string
  default     = null
}

variable "jenkins_associate_public_ip" {
  description = "Associate a public IP address to Jenkins instance"
  type        = bool
  default     = true
}
