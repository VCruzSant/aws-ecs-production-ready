variable "name" {
  description = "Name of the cluster, service and task family, and prefix of the roles, security group and log group."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{0,50}$", var.name))
    error_message = "name must be 1 to 51 letters, digits, hyphens or underscores (IAM role names get a suffix)."
  }
}

variable "vpc_id" {
  description = "ID of the VPC."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets the tasks run in."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) >= 1
    error_message = "At least one private subnet is required."
  }
}

variable "alb_security_group_id" {
  description = "Security group of the load balancer, the only allowed source of inbound traffic."
  type        = string
}

variable "target_group_arn" {
  description = "Target group the service registers its tasks in."
  type        = string
}

variable "ecr_repository_arn" {
  description = "ECR repository the execution role is allowed to pull from."
  type        = string
}

variable "image" {
  description = "Full image reference, e.g. \"<account>.dkr.ecr.<region>.amazonaws.com/my-app:abc1234\"."
  type        = string
  default     = null

  validation {
    condition     = !endswith(coalesce(var.image, "-"), ":latest")
    error_message = "Use an immutable tag (e.g. the git SHA), not \"latest\"."
  }
}

variable "container_name" {
  description = "Name of the container in the task definition."
  type        = string
  default     = "app"
}

variable "container_port" {
  description = "Port the app listens on."
  type        = number
  default     = 8000
}

variable "environment" {
  description = "Plain environment variables for the container (no secrets)."
  type        = map(string)
  default     = {}
}

variable "cpu" {
  description = "Task CPU units (256 = 0.25 vCPU)."
  type        = number
  default     = 256
}

variable "memory" {
  description = "Task memory in MiB; must be a valid pair with cpu."
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Number of tasks to keep running."
  type        = number
  default     = 1

  validation {
    condition     = var.desired_count >= 0
    error_message = "desired_count cannot be negative."
  }
}

variable "health_check_grace_period_seconds" {
  description = "Seconds ECS ignores failing load balancer health checks after a task starts. The app is ready in a few seconds."
  type        = number
  default     = 30
}

variable "container_insights" {
  description = "Enable CloudWatch Container Insights on the cluster (extra cost per metric)."
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "Retention of the container logs in CloudWatch Logs."
  type        = number
  default     = 7

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365], var.log_retention_days)
    error_message = "log_retention_days must be a CloudWatch Logs retention value up to 365."
  }
}

variable "wait_for_steady_state" {
  description = "Make terraform apply wait until the service has its tasks running and healthy."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Extra tags merged into every resource (on top of the provider default tags)."
  type        = map(string)
  default     = {}
}
