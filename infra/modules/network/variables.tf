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
    # Subnets can be no smaller than /28 and need room for the private blocks.
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

variable "enable_flow_logs" {
  description = "Send VPC Flow Logs to a CloudWatch log group created by this module."
  type        = bool
  default     = true
}

variable "flow_logs_traffic_type" {
  description = "Traffic recorded by the flow logs: REJECT (cheapest, shows blocked connections), ACCEPT or ALL."
  type        = string
  default     = "REJECT"

  validation {
    condition     = contains(["ACCEPT", "REJECT", "ALL"], var.flow_logs_traffic_type)
    error_message = "flow_logs_traffic_type must be ACCEPT, REJECT or ALL."
  }
}

variable "flow_logs_retention_days" {
  description = "Retention of the flow logs in CloudWatch Logs."
  type        = number
  default     = 7

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365], var.flow_logs_retention_days)
    error_message = "flow_logs_retention_days must be a CloudWatch Logs retention value up to 365."
  }
}

variable "tags" {
  description = "Extra tags merged into every resource (on top of the provider default tags)."
  type        = map(string)
  default     = {}
}
