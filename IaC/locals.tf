locals {
  env             = "prod"
  location        = var.location
  region_code     = "ne"
  rg_name         = "gosofia-${local.env}-${local.region_code}-rg"
  tags = {
    project     = "GoSofia"
    environment = local.env
    managedby   = "Terraform"
    owner       = "Svetoslav"
  }
}
