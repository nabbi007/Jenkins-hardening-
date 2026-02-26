variable "project_name" {
  description = "Project name for tagging"
  type        = string
}

variable "repositories" {
  description = "List of ECR repositories to create"
  type        = list(string)
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
