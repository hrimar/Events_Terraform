variable "subscription_id" {
  type        = string
  description = "Azure Subscription ID."
}

variable "os_type" {
  type        = string
  default     = "Linux"
  description = "Operating system type for the service plans."  
}

variable "sql_admin_login" {
  type        = string
  description = "SQL Server administrator login."  
}

variable "sql_admin_password" {
  type        = string
  description = "SQL Server administrator password."  
}

variable "hristo_ip_address" {
  type        = string
  description = "Your public IP address to allow access to SQL Server."
}

variable "groq_api_key" {
  type        = string
  description = "API key for Groq service."
}

variable "developer_object_id" {
  type        = string
  description = "Azure AD Object ID of the developer to be added as SQL Admin in the group."
  
}

variable "ci_cd_sp_id" {
  type        = string
  description = "Service Principal ID for CI/CD pipeline to be added as SQL Admin in the group."
  
}