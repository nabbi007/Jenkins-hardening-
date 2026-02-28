variable "project_name" {
  description = "Project name for tagging"
  type        = string
}

variable "repositories" {
  description = "List of ECR repositories to manage/use"
  type        = list(string)
}

variable "create_repositories" {
  description = "Create ECR repositories when true; when false, reuse existing repositories by name"
  type        = bool
  default     = false
}

variable "image_tag_mutability" {
  description = "ECR image tag mutability"
  type        = string
  default     = "MUTABLE"
}

variable "lifecycle_keep_images" {
  description = "Number of images to keep"
  type        = number
  default     = 30
}
