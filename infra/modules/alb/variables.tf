variable "name" {
  description = "Name of the load balancer, its target group and the prefix of its security group."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9]([A-Za-z0-9-]{0,30}[A-Za-z0-9])?$", var.name))
    error_message = "name must be 1 to 32 letters, digits or hyphens, not starting or ending with a hyphen (AWS load balancer limit)."
  }
}

variable "vpc_id" {
  description = "ID of the VPC."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnets for the load balancer, in at least two AZs."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_ids) >= 2
    error_message = "An Application Load Balancer needs subnets in at least two AZs."
  }
}

variable "app_port" {
  description = "Port the app listens on inside the tasks."
  type        = number
  default     = 8000
}

variable "app_security_group_id" {
  description = "Security group of the app tasks, the only egress destination of the load balancer."
  type        = string
}

variable "health_check_path" {
  description = "Path the target group calls to decide if a task is healthy."
  type        = string
  default     = "/health"
}

variable "deregistration_delay" {
  description = "Seconds to drain in-flight requests from a task before it is removed."
  type        = number
  default     = 30
}

variable "enable_deletion_protection" {
  description = "Block deletion of the load balancer (turn on in production)."
  type        = bool
  default     = false
}

variable "access_logs_enabled" {
  description = "Write access logs to a dedicated S3 bucket created by this module."
  type        = bool
  default     = true
}

variable "access_logs_retention_days" {
  description = "Days before access log objects expire."
  type        = number
  default     = 7

  validation {
    condition     = var.access_logs_retention_days >= 1
    error_message = "access_logs_retention_days must be at least 1."
  }
}

variable "tags" {
  description = "Extra tags merged into every resource (on top of the provider default tags)."
  type        = map(string)
  default     = {}
}
