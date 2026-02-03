variable "dotnet_version" {
  description = "The .NET version for the app service."
  type        = string
  default     = "8.0"
}

variable "http2_enabled" {
  description = "Enable HTTP/2 for the app service."
  type        = bool
  default     = true
}

variable "min_tls_version" {
  description = "The minimum TLS version to support."
  type        = string
  default     = "1.2"
}

variable "ftps_state" {
  description = "The FTPS state for the app service."
  type        = string
  default     = "Disabled"
}
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

variable "smtp_host" {
  type        = string
  description = "SMTP server host."
}
variable "smtp_port" {
  type        = number
  description = "SMTP server port."
}
variable "smtp_username" {
  type        = string
  description = "SMTP server username."
}
variable "smtp_password" {
  type        = string
  description = "SMTP server password."
}
variable "smtp_from_address" {
  type        = string
  description = "SMTP server from address."
}
variable "smtp_use_ssl" {
  type        = bool
  description = "Use SSL for SMTP."
}
variable "smtp_use_tls" {
  type        = bool
  description = "Use TLS for SMTP."
}
variable "use_default_credentials" {
  type        = bool
  description = "Use default credentials for SMTP."
}
variable "display_name" {
  type        = string
  description = "Display name for SMTP."
}
