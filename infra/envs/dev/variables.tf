variable "region" {
  description = "AWS region of the environment."
  type        = string
  default     = "us-east-2"
}

variable "project" {
  description = "Project name, used in the default tags."
  type        = string
  default     = "aws-ecs-production-ready"
}

variable "environment" {
  description = "Environment name, used in the default tags and resource names."
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of Availability Zones."
  type        = number
  default     = 2
}

variable "enable_nat_gateway" {
  description = "Create NAT Gateway(s) for the private subnets."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "One shared NAT Gateway (cheaper) instead of one per AZ."
  type        = bool
  default     = true
}

variable "enable_flow_logs" {
  description = "Record rejected VPC traffic in CloudWatch Logs (7 days)."
  type        = bool
  default     = true
}

variable "alb_access_logs" {
  description = "Write load balancer access logs to a dedicated S3 bucket (7 days)."
  type        = bool
  default     = true
}

# Null only while the repository is created on its own, before the first image exists.
variable "image_tag" {
  description = "Tag of the app image in ECR to deploy (the short git SHA pushed by make image-push)."
  type        = string
  default     = null

  validation {
    condition     = var.image_tag == null || (can(regex("^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$", var.image_tag)) && var.image_tag != "latest")
    error_message = "image_tag must be a valid Docker tag other than \"latest\"."
  }
}

variable "app_port" {
  description = "Port the app listens on."
  type        = number
  default     = 8000
}

variable "task_cpu" {
  description = "Task CPU units (256 = 0.25 vCPU)."
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Task memory in MiB."
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Number of app tasks."
  type        = number
  default     = 1
}

variable "container_insights" {
  description = "Enable CloudWatch Container Insights (extra cost, needed by the running tasks alarm)."
  type        = bool
  default     = true
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_multi_az" {
  description = "Run the database with a standby in a second AZ (doubles its cost)."
  type        = bool
  default     = false
}

variable "alert_emails" {
  description = "E-mail addresses that receive the CloudWatch alarms (each must confirm the SNS subscription)."
  type        = list(string)
}
