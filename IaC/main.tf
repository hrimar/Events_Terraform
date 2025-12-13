# Resource Group
resource "azurerm_resource_group" "rg" {
  name     = local.rg_name
  location = local.location
  tags     = local.tags
}

# Web App Service Plan
resource "azurerm_service_plan" "web_plan" {
  name                = local.app_plan_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  os_type             = var.os_type
  sku_name            = "B1" # Basic tier for minimal cost
}

# Function App Service Plan
resource "azurerm_service_plan" "func_plan" {
  name                = local.func_plane_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  os_type             = var.os_type
  sku_name            = "Y1" # Consumption plan
}

# Web App
resource "azurerm_linux_web_app" "web_app" {
  name                = local.app_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  service_plan_id     = azurerm_service_plan.web_plan.id

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on = true
    application_stack {
      dotnet_version = "6.0"
    }
  }

  tags = local.tags
}

# Storage Account for Function App
resource "azurerm_storage_account" "func_storage" {
  name                     = local.func_storage_name
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = local.tags
}

# Function App
resource "azurerm_linux_function_app" "func_app" {
  name                       = local.func_app_name
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  service_plan_id            = azurerm_service_plan.func_plan.id
  storage_account_name       = azurerm_storage_account.func_storage.name # a required min storage for the Function App!!!
  storage_account_access_key = azurerm_storage_account.func_storage.primary_access_key

  identity {
    type = "SystemAssigned"
  }

  site_config {
    application_stack {
      dotnet_version = "8.0"
    }
  }

  tags = local.tags
}

# SQL Server
resource "azurerm_mssql_server" "sql" {
  name                         = local.sql_name
  resource_group_name          = azurerm_resource_group.rg.name
  location                     = azurerm_resource_group.rg.location
  version                      = "12.0"
  administrator_login          = var.sql_admin_login
  administrator_login_password = var.sql_admin_password

  tags = local.tags
}

resource "azurerm_mssql_firewall_rule" "allow_my_ip" {
  name             = "AllowMyIP"
  server_id        = azurerm_mssql_server.sql.id
  start_ip_address = var.hristo_ip_address
  end_ip_address   = var.hristo_ip_address
}

# SQL Database
resource "azurerm_mssql_database" "db" {
  name      = local.db_name
  server_id = azurerm_mssql_server.sql.id
  sku_name  = "Basic"

  tags = local.tags
}
