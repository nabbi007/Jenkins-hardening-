variable "project_name" {
  description = "Project name for tags"
  type        = string
}

variable "ecs_cluster_name" {
  description = "ECS cluster name"
  type        = string
}

variable "ecs_service_name" {
  description = "ECS service name"
  type        = string
}

variable "alarm_sns_topic_arn" {
  description = "Optional SNS topic ARN for alarms"
  type        = string
  default     = null
}

variable "cpu_alarm_threshold" {
  description = "CPU alarm threshold"
  type        = number
  default     = 80
}

variable "memory_alarm_threshold" {
  description = "Memory alarm threshold"
  type        = number
  default     = 80
}
