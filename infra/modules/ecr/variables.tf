variable "name" {
  description = "Name of the repository (lowercase, e.g. \"my-app-dev\")."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+(?:[._-][a-z0-9]+)*(?:/[a-z0-9]+(?:[._-][a-z0-9]+)*)*$", var.name))
    error_message = "name must be lowercase letters, digits and . _ - / separators."
  }
}

variable "max_image_count" {
  description = "Number of most recent images to keep; older ones are expired by the lifecycle policy."
  type        = number
  default     = 10

  validation {
    condition     = var.max_image_count >= 1
    error_message = "max_image_count must be at least 1."
  }
}

variable "force_delete" {
  description = "Delete the repository on destroy even if it still contains images."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Extra tags for the repository (on top of the provider default tags)."
  type        = map(string)
  default     = {}
}
