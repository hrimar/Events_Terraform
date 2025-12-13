variable "subscription_id" {
  type        = string
  description = "Azure Subscription ID."
}

variable "location" {
  type        = string
  default     = "northeurope"
  description = "Azure region for resources."
}
