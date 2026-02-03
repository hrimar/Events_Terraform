locals {
  env               = "prod"
  environment       = "Production"
  location          = "westeurope"
  region_code       = "we"
  rg_name           = "gosofia-${local.env}-${local.region_code}-rg"
  app_plan_name     = "gosofia-${local.env}-${local.region_code}-plan"
  app_name          = "gosofia-${local.env}-${local.region_code}-app"
  sql_name          = "gosofia-${local.env}-${local.region_code}-sql"
  db_name           = "gosofia-${local.env}-${local.region_code}-db"
  storage_name      = "gosofiastorage${local.env}${local.region_code}"
  # func_plane_name   = "gosofia-${local.env}-${local.region_code}-func-plan"
  # func_app_name     = "gosofia-${local.env}-${local.region_code}-func-app"
  # func_storage_name = "gosofiafuncstorage"
  tags = {
    project     = "GoSofia"
    environment = local.env
    managedby   = "Terraform"
    owner       = "Svetoslav"
  }
}
