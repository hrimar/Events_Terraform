output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.rg.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.rg.location
}

output "events_storage_account_name" {
  value = azurerm_storage_account.events_storage.name
}

output "events_storage_account_connection_string" {
  value = azurerm_storage_account.events_storage.primary_connection_string
  sensitive = true
}

# Output Web App Managed Identity for verification
output "web_app_managed_identity_principal_id" {
  value       = azurerm_linux_web_app.web_app.identity[0].principal_id
  description = "Principal ID of Web App Managed Identity for Storage Blob access"
}