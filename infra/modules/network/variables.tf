variable "name" {
  description = "Name prefix for every resource (e.g. \"aws-ecs-prod-ready-dev\")."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition = (
      can(cidrnetmask(var.vpc_cidr)) &&
      tonumber(split("/", var.vpc_cidr)[1]) >= 16 &&
      tonumber(split("/", var.vpc_cidr)[1]) <= 28
    )
    error_message = "vpc_cidr must be an IPv4 CIDR block between /16 and /28 (AWS VPC limits)."
  }
}

variable "az_count" {
  description = "Number of Availability Zones to spread the subnets across (one public and one private subnet per AZ)."
  type        = number
  default     = 2

  validation {
    # Load balancers and RDS subnet groups need at least two AZs.
    condition     = var.az_count >= 2 && var.az_count <= 4
    error_message = "az_count must be between 2 and 4."
  }
}

variable "subnet_newbits" {
  description = "Bits added to the VPC prefix to size each subnet. With a /16 VPC, 8 gives /24 subnets (251 usable IPs each)."
  type        = number
  default     = 8

  validation {
    # Subnets can't be smaller than /28, and there must be room for the private
    # subnets, which start at block 10.
    condition = (
      tonumber(split("/", var.vpc_cidr)[1]) + var.subnet_newbits <= 28 &&
      pow(2, var.subnet_newbits) >= 10 + var.az_count
    )
    error_message = "subnet_newbits must leave subnets of /28 or larger and room for 10 + az_count subnets."
  }
}

variable "enable_nat_gateway" {
  description = "Create NAT Gateway(s) so private subnets can reach the internet (pull images, call APIs)."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Use one shared NAT Gateway for all private subnets (cheaper) instead of one per AZ (highly available)."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Extra tags merged into every resource (on top of the provider default tags)."
  type        = map(string)
  default     = {}
}
