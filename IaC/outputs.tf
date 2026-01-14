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