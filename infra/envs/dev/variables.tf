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
