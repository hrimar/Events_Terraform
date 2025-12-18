locals {
  env               = "prod"
  db_location       = "northeurope" # missing free quota in North Europe for Plans, so they will be in West Europe for now
  location          = "westeurope"  # missing free quota for SQL in West Europe, move all here from North Europe after starting Pay-as-you-go plan
  region_code       = "we"          # missing free quota for SQL in West Europe, move all here from North Europe after starting Pay-as-you-go plan
  rg_name           = "gosofia-${local.env}-${local.region_code}-rg"
  app_plan_name     = "gosofia-${local.env}-${local.region_code}-plan"
  app_name          = "gosofia-${local.env}-${local.region_code}-app"
  func_plane_name   = "gosofia-${local.env}-${local.region_code}-func-plan"
  func_app_name     = "gosofia-${local.env}-${local.region_code}-func-app"
  func_storage_name = "gosofiafuncstorage"
  sql_name          = "gosofia-${local.env}-${local.region_code}-sql-1"
  db_name           = "gosofia-${local.env}-${local.region_code}-db-1"
  tags = {
    project     = "GoSofia"
    environment = local.env
    managedby   = "Terraform"
    owner       = "Svetoslav"
  }
}
