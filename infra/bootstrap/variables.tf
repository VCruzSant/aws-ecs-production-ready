variable "region" {
  description = "AWS region for the state bucket and the budget."
  type        = string
  default     = "us-east-2"
}

variable "project" {
  description = "Project name, used in the default tags."
  type        = string
  default     = "aws-ecs-production-ready"
}

variable "state_bucket_prefix" {
  description = "Prefix of the state bucket name. The account ID is appended to keep it globally unique."
  type        = string
  default     = "aws-ecs-prod-ready-tfstate"
}

variable "monthly_budget_usd" {
  description = "Monthly cost budget in USD."
  type        = number
  default     = 10
}

variable "budget_alert_emails" {
  description = "E-mail addresses that receive the budget alerts."
  type        = list(string)

  validation {
    condition     = length(var.budget_alert_emails) > 0
    error_message = "Provide at least one e-mail address for the budget alerts."
  }
}

variable "noncurrent_version_retention_days" {
  description = "Days to keep old versions of the state files before they are deleted."
  type        = number
  default     = 90
}
