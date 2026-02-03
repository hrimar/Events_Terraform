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

  tags = local.tags
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

  https_only = true
  site_config {
    always_on       = true
    http2_enabled   = var.http2_enabled
    ftps_state      = var.ftps_state
    application_stack {
      dotnet_version = var.dotnet_version
    }
  }

  connection_string {
    name  = "EventsConnection"
    type  = "SQLServer"
    value = "Server=tcp:${azurerm_mssql_server.sql.fully_qualified_domain_name},1433;Initial Catalog=${azurerm_mssql_database.db.name};Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;Authentication=Active Directory Default;"
  }

  app_settings = {
    "BlobStorage__Uri"            = azurerm_storage_account.events_storage.primary_blob_endpoint
    "Smtp__From"                  = var.smtp_from_address
    "Smtp_DisplayName"            = var.display_name
    "Smtp__Host"                  = var.smtp_host
    "Smtp__Port"                  = var.smtp_port
    "Smtp__UserName"              = var.smtp_username
    "Smtp__Password"              = var.smtp_password
    "Smtp__UseDefaultCredentials" = var.use_default_credentials
    "Smtp__UseSsl"                = var.smtp_use_ssl
    "Smtp__UseTls"                = var.smtp_use_tls
    "ASPNETCORE_ENVIRONMENT"      = local.environment
  }

  tags = local.tags
}

# SQL Server with AAD Admin
resource "azurerm_mssql_server" "sql" {
  name                          = local.sql_name
  resource_group_name           = azurerm_resource_group.rg.name
  location                      = azurerm_resource_group.rg.location
  version                       = "12.0"
  administrator_login           = var.sql_admin_login
  administrator_login_password  = var.sql_admin_password
  public_network_access_enabled = true # Enabled for development

  azuread_administrator {
    login_username = azuread_group.sql_admins.display_name
    object_id      = azuread_group.sql_admins.object_id
  }

  tags = local.tags
}

# Assign CI/CD Service Principal the "SQL Server Contributor" role
resource "azurerm_role_assignment" "ci_cd_sql_contributor" {
  scope                = azurerm_mssql_server.sql.id
  role_definition_name = "SQL Server Contributor"
  principal_id         = var.ci_cd_sp_id
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

  lifecycle {
    prevent_destroy = true # Safety net!
  }

  tags = local.tags
}

# AAD Administrators Group
resource "azuread_group" "sql_admins" {
  display_name     = "SQL-Administrators"
  security_enabled = true
  description      = "SQL Database Administrators"
}

# Add current user as member (from Azure CLI login)
resource "azuread_group_member" "developer_user" {
  group_object_id  = azuread_group.sql_admins.object_id
  member_object_id = var.developer_object_id
}

# Add Service Principal as member
resource "azuread_group_member" "pipeline_service_principal" {
  group_object_id  = azuread_group.sql_admins.object_id
  member_object_id = var.ci_cd_sp_id
}

# Storage Account for Event Images and Thumbnails
resource "azurerm_storage_account" "events_storage" {
  name                     = local.storage_name
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = local.tags
}

resource "azurerm_storage_container" "event_images" {
  name               = "event-images" // single container for original images and thumbnails in different virtual folders
  storage_account_id = azurerm_storage_account.events_storage.id
  # container_access_type = "private" # read and write access via Azure SDK/API withkey or SAS token
  container_access_type = "blob" # allow public read access for blobs (images)
}

# Assign Web App Managed Identity the "Storage Blob Data Contributor" role
resource "azurerm_role_assignment" "webapp_storage_blob_contributor" {
  scope                = azurerm_storage_account.events_storage.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_web_app.web_app.identity[0].principal_id
}

# Assign Developer User the "Storage Blob Data Contributor" role for development
resource "azurerm_role_assignment" "developer_storage_blob_contributor" {
  scope                = azurerm_storage_account.events_storage.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.developer_object_id
}

# ========================================
# # # # Function App Service Plan (Consumption Plan) // old and not working with Playwright
# # # resource "azurerm_service_plan" "func_plan" {
# # #   name                = local.func_plane_name
# # #   location            = azurerm_resource_group.rg.location
# # #   resource_group_name = azurerm_resource_group.rg.name
# # #   os_type             = var.os_type
# # #   sku_name            = "Y1" # Consumption plan
# # # }
# # Function App Service Plan - Elastic Premium Tier 1
# resource "azurerm_service_plan" "func_plan" {
#   name                = local.func_plane_name
#   location            = azurerm_resource_group.rg.location
#   resource_group_name = azurerm_resource_group.rg.name
#   os_type             = var.os_type
#   sku_name            = "EP1"

#   # Optional: Auto-scale settings
#   maximum_elastic_worker_count = 1 # Max instances.  1 instance = ~150 EUR/месец

#   tags = local.tags
# }
# # # Function App Service Plan -> with this plan Playwright can't install Chromium, because B2 plan hasn't access to system packages (apt-get, etc.)
# # resource "azurerm_service_plan" "func_plan" {
# #   name                = local.func_plane_name
# #   location            = azurerm_resource_group.rg.location
# #   resource_group_name = azurerm_resource_group.rg.name
# #   os_type             = var.os_type
# #   sku_name            = "B2" # Standard tier - 3.5 GB RAM (вместо EP1)

# #   tags = local.tags
# # }

# # Storage Account for Function App
# resource "azurerm_storage_account" "func_storage" {
#   name                     = local.func_storage_name
#   resource_group_name      = azurerm_resource_group.rg.name
#   location                 = azurerm_resource_group.rg.location
#   account_tier             = "Standard"
#   account_replication_type = "LRS"

#   tags = local.tags
# }

# # Function App
# resource "azurerm_linux_function_app" "func_app" {
#   name                       = local.func_app_name
#   location                   = azurerm_resource_group.rg.location
#   resource_group_name        = azurerm_resource_group.rg.name
#   service_plan_id            = azurerm_service_plan.func_plan.id
#   storage_account_name       = azurerm_storage_account.func_storage.name # a required min storage for the Function App
#   storage_account_access_key = azurerm_storage_account.func_storage.primary_access_key

#   identity {
#     type = "SystemAssigned"
#   }

#   site_config {
#     always_on = true # Important for EP1!
#     application_stack {
#       dotnet_version              = "8.0"
#       use_dotnet_isolated_runtime = true
#     }
#     # Enable custom startup command for Playwright
#     app_command_line = ""
#   }
#   # site_config {
#   #   always_on        = true
#   #   linux_fx_version = "DOCKER|<your-container-registry>/<image>:<tag>" // TODO:
#   #   # or public Docker Hub: "DOCKER|username/image:tag"
#   # }

#   connection_string {
#     name  = "EventsConnection"
#     type  = "SQLServer"
#     value = "Server=tcp:${azurerm_mssql_server.sql.fully_qualified_domain_name},1433;Initial Catalog=${azurerm_mssql_database.db.name};User ID=${var.sql_admin_login};Password=${var.sql_admin_password};Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
#   }

#   app_settings = {
#     "FUNCTIONS_WORKER_RUNTIME"                 = "dotnet-isolated"
#     "FUNCTIONS_EXTENSION_VERSION"              = "~4"
#     "AzureWebJobsStorage"                      = azurerm_storage_account.func_storage.primary_connection_string
#     "WEBSITE_CONTENTAZUREFILECONNECTIONSTRING" = azurerm_storage_account.func_storage.primary_connection_string
#     "WEBSITE_CONTENTSHARE"                     = local.func_app_name
#     "FUNCTIONS_WORKER_PROCESS_COUNT"           = "1"
#     "AzureFunctionsJobHost__functionTimeout"   = "00:10:00"
#     "Groq__ApiKey"                             = var.groq_api_key
#     "SCM_DO_BUILD_DURING_DEPLOYMENT"           = "false"
#     "ENABLE_ORYX_BUILD"                        = "false"
#     "WEBSITE_USE_PLACEHOLDER_DOTNETISOLATED"   = "1"
#     "APPLICATIONINSIGHTS_CONNECTION_STRING"    = azurerm_application_insights.func_insights.connection_string
#     # Playwright settings
#     "PLAYWRIGHT_BROWSERS_PATH"         = "/home/site/wwwroot/playwright_browsers"
#     "PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD" = "0"
#   }

#   tags = local.tags
# }

# # Application Insights for Function App
# resource "azurerm_application_insights" "func_insights" {
#   name                = "${local.func_app_name}-insights"
#   location            = azurerm_resource_group.rg.location
#   resource_group_name = azurerm_resource_group.rg.name
#   application_type    = "web"

#   tags = local.tags
# }
