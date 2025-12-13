locals {
  env               = "prod"
  location          = "northeurope"
  region_code       = "ne"
  rg_name           = "gosofia-${local.env}-${local.region_code}-rg"
  app_plan_name     = "gosofia-${local.env}-${local.region_code}-plan"
  app_name          = "gosofia-${local.env}-${local.region_code}-app"
  func_plane_name   = "gosofia-${local.env}-${local.region_code}-func-plan"
  func_app_name     = "gosofia-${local.env}-${local.region_code}-func-app"
  func_storage_name = "gosofiafuncstorage"
  sql_name          = "gosofia-${local.env}-${local.region_code}-sql"
  db_name           = "gosofia-${local.env}-${local.region_code}-db"
  tags = {
    project     = "GoSofia"
    environment = local.env
    managedby   = "Terraform"
    owner       = "Svetoslav"
  }
}
