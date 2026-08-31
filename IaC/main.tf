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
    always_on                         = true
    http2_enabled                     = var.http2_enabled
    ftps_state                        = var.ftps_state
    health_check_path                 = "/health"
    health_check_eviction_time_in_min = 10
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
    "BlobStorage__Uri"                      = azurerm_storage_account.events_storage.primary_blob_endpoint
    "Smtp__From"                            = var.smtp_from_address
    "Smtp_DisplayName"                      = var.display_name
    "Smtp__Host"                            = var.smtp_host
    "Smtp__Port"                            = var.smtp_port
    "Smtp__UserName"                        = var.smtp_username
    "Smtp__Password"                        = var.smtp_password
    "Smtp__UseDefaultCredentials"           = var.use_default_credentials
    "Smtp__UseSsl"                          = var.smtp_use_ssl
    "Smtp__UseTls"                          = var.smtp_use_tls
    "ASPNETCORE_ENVIRONMENT"                = local.environment
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.web_insights.connection_string
  }

  tags = local.tags
}

# Apex custom domain (go-sofia.com) - free Azure Managed Certificate + SNI binding.
# Originally created manually in the Azure Portal (2026-08-28) to fix the apex domain not
# resolving; adopted here via `terraform import` so it isn't orphaned/lost on a future apply.
# www.go-sofia.com's binding/certificate predate this Terraform project and are still
# unmanaged - left as-is, not part of this change.
resource "azurerm_app_service_custom_hostname_binding" "apex" {
  hostname            = "go-sofia.com"
  app_service_name    = azurerm_linux_web_app.web_app.name
  resource_group_name = azurerm_resource_group.rg.name

  # SSL is attached separately via azurerm_app_service_certificate_binding below - changing
  # this later would conflict with that resource.
  lifecycle {
    ignore_changes = [ssl_state, thumbprint]
  }
}

resource "azurerm_app_service_managed_certificate" "apex" {
  # No tags: Azure App Service Managed Certificates (the free, auto-renewing kind) don't
  # persist tags - the API accepts a tags update and reports success, but never actually
  # stores them, so declaring any here would show as permanent drift on every plan.
  custom_hostname_binding_id = azurerm_app_service_custom_hostname_binding.apex.id
}

resource "azurerm_app_service_certificate_binding" "apex" {
  hostname_binding_id = azurerm_app_service_custom_hostname_binding.apex.id
  certificate_id      = azurerm_app_service_managed_certificate.apex.id
  ssl_state           = "SniEnabled"
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
  name                  = "event-images" // single container for original images and thumbnails in different virtual folders
  storage_account_id    = azurerm_storage_account.events_storage.id
  container_access_type = "blob" # public read for images
  # container_access_type = "private" # read and write access via Azure SDK/API withkey or SAS token
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
#   #   linux_fx_version = "DOCKER|<your-container-registry>/<image>:<tag>" //
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

# =============================================================================
# Crawler Container Resources
# Replace the old Function App (EP1 Premium Plan, ~$150/month).
# Container Apps Job runs only ~3 min/day → < $1/month.
# Deployed via GitHub Actions (see .github/workflows/crawler-deploy-production.yml).
# =============================================================================

# Azure Container Registry — stores the crawler Docker image
resource "azurerm_container_registry" "acr" {
  name                = local.acr_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Basic"
  admin_enabled       = true

  tags = local.tags
}

# Assign CI/CD Service Principal the "AcrPush" role — needed by GitHub Actions pipeline
# to push the crawler Docker image to the registry on each deployment.
resource "azurerm_role_assignment" "ci_cd_acr_push" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPush"
  principal_id         = var.ci_cd_sp_id
}

# Log Analytics Workspace — receives logs from the Container Apps Environment
resource "azurerm_log_analytics_workspace" "crawler_logs" {
  name                = local.crawler_log_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = local.tags
}

# Container Apps Environment — shared networking and logging layer for container jobs/apps
resource "azurerm_container_app_environment" "cae" {
  name                       = local.cae_name
  resource_group_name        = azurerm_resource_group.rg.name
  location                   = azurerm_resource_group.rg.location
  log_analytics_workspace_id = azurerm_log_analytics_workspace.crawler_logs.id

  tags = local.tags
}

# Container Apps Job — runs the crawler on a daily cron schedule (01:00 UTC)
resource "azurerm_container_app_job" "crawler_job" {
  name                         = local.crawler_job_name
  resource_group_name          = azurerm_resource_group.rg.name
  location                     = azurerm_resource_group.rg.location
  container_app_environment_id = azurerm_container_app_environment.cae.id

  replica_timeout_in_seconds = 1800 # 30 min max — crawler typically finishes in ~10 min
  replica_retry_limit        = 1

  schedule_trigger_config {
    cron_expression          = "0 1 * * *"
    parallelism              = 1
    replica_completion_count = 1
  }

  registry {
    server               = azurerm_container_registry.acr.login_server
    username             = azurerm_container_registry.acr.admin_username
    password_secret_name = "acr-password"
  }

  secret {
    name  = "acr-password"
    value = azurerm_container_registry.acr.admin_password
  }

  template {
    container {
      name   = local.crawler_job_name
      image  = "${azurerm_container_registry.acr.login_server}/events-crawler:${var.crawler_image_tag}"
      cpu    = 1.0
      memory = "2Gi"

      env {
        name  = "FUNCTIONS_WORKER_RUNTIME"
        value = "dotnet-isolated"
      }
      env {
        name  = "ASPNETCORE_ENVIRONMENT"
        value = local.environment
      }
      env {
        name  = "PLAYWRIGHT_BROWSERS_PATH"
        value = "/home/site/wwwroot/.playwright"
      }
      env {
        name  = "AzureWebJobsStorage"
        value = azurerm_storage_account.events_storage.primary_connection_string
      }
      env {
        name  = "ConnectionStrings__EventsConnection"
        value = var.crawler_sql_connection_string
      }
      env {
        name  = "Claude__ApiKey"
        value = var.claude_api_key
      }
      env {
        name  = "Groq__ApiKey"
        value = var.groq_api_key
      }
    }
  }

  tags = local.tags

  # The image tag is owned by the crawler-deploy-production.yml GitHub Actions workflow, which
  # runs "az containerapp job update --image ...:<commit-SHA>" directly against Azure on every
  # push (bypassing Terraform state) for deterministic, traceable deploys. Without this, every
  # terraform plan/apply would revert the image back to var.crawler_image_tag (default "latest"),
  # fighting the CI/CD pipeline. Terraform still creates/manages the job with that default on
  # first apply; after that, the image is CI/CD's responsibility.
  lifecycle {
    ignore_changes = [template[0].container[0].image]
  }
}

# =============================================================================
# Observability: Application Insights, HTTP logs, and Azure Monitor alerts for the Web App,
# all feeding the same Log Analytics workspace already used for crawler logs.
# =============================================================================

# Application Insights for Events.Web - shares the existing Log Analytics
# workspace (azurerm_log_analytics_workspace.crawler_logs) rather than creating
# a second one, so all app + crawler telemetry lives in one place to query.
resource "azurerm_application_insights" "web_insights" {
  name                = "${local.app_name}-insights"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  workspace_id        = azurerm_log_analytics_workspace.crawler_logs.id
  application_type    = "web"

  tags = local.tags
}

# Sends App Service HTTP/console/application logs to Log Analytics, queryable
# via KQL (the same way crawler container logs already are).
resource "azurerm_monitor_diagnostic_setting" "web_app_logs" {
  name                       = "${local.app_name}-diagnostics"
  target_resource_id         = azurerm_linux_web_app.web_app.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.crawler_logs.id

  enabled_log {
    category = "AppServiceHTTPLogs"
  }

  enabled_log {
    category = "AppServiceConsoleLogs"
  }

  enabled_log {
    category = "AppServiceAppLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

# Email notification target for all alerts below.
resource "azurerm_monitor_action_group" "ops_alerts" {
  name                = "gosofia-${local.env}-${local.region_code}-alerts-ag"
  resource_group_name = azurerm_resource_group.rg.name
  short_name          = "gosofiaops"

  email_receiver {
    name          = "primary"
    email_address = var.alert_email
  }

  tags = local.tags
}

# Thresholds are a starting point (no real traffic baseline existed before this
# incident) - recalibrate once Application Insights has real data.
resource "azurerm_monitor_metric_alert" "sql_dtu_high" {
  name                = "gosofia-${local.env}-${local.region_code}-sql-dtu-high"
  resource_group_name = azurerm_resource_group.rg.name
  scopes              = [azurerm_mssql_database.db.id]
  description         = "SQL Database DTU consumption above 80% for 5 minutes"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.Sql/servers/databases"
    metric_name      = "dtu_consumption_percent"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = azurerm_monitor_action_group.ops_alerts.id
  }

  tags = local.tags
}

resource "azurerm_monitor_metric_alert" "sql_workers_high" {
  name                = "gosofia-${local.env}-${local.region_code}-sql-workers-high"
  resource_group_name = azurerm_resource_group.rg.name
  scopes              = [azurerm_mssql_database.db.id]
  description         = "SQL Database worker consumption above 80% for 5 minutes - this is the exact metric that hit its limit during the 2026-08-25 incident."
  severity            = 1
  frequency           = "PT5M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.Sql/servers/databases"
    metric_name      = "workers_percent"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = azurerm_monitor_action_group.ops_alerts.id
  }

  tags = local.tags
}

resource "azurerm_monitor_metric_alert" "app_cpu_high" {
  name                = "gosofia-${local.env}-${local.region_code}-app-cpu-high"
  resource_group_name = azurerm_resource_group.rg.name
  scopes              = [azurerm_service_plan.web_plan.id]
  description         = "App Service Plan CPU above 80% for 5 minutes"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.Web/serverfarms"
    metric_name      = "CpuPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = azurerm_monitor_action_group.ops_alerts.id
  }

  tags = local.tags
}

resource "azurerm_monitor_metric_alert" "app_5xx_high" {
  name                = "gosofia-${local.env}-${local.region_code}-app-5xx-high"
  resource_group_name = azurerm_resource_group.rg.name
  scopes              = [azurerm_linux_web_app.web_app.id]
  description         = "App Service returning more than 5 server errors (5xx) within 5 minutes"
  severity            = 1
  frequency           = "PT5M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 5
  }

  action {
    action_group_id = azurerm_monitor_action_group.ops_alerts.id
  }

  tags = local.tags
}
