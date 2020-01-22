#------------------------------------------------------------------------------
# provider
#------------------------------------------------------------------------------
provider "aws" {
  region = var.region
}

#------------------------------------------------------------------------------
# terraform
#------------------------------------------------------------------------------
terraform {
  required_version = ">= 0.12"
  required_providers {
    aws = ">= 2.24.0"
  }
}

#------------------------------------------------------------------------------
# data
#------------------------------------------------------------------------------
# get amazon credentials
data "aws_caller_identity" "current" {}

locals {
  common_tags = {}
}

#------------------------------------------------------------------------------
# modules
#------------------------------------------------------------------------------
module "sonarqube" {
  source             = "./modules/sonarqube"
  region             = var.region
  vpc_id             = var.vpc_id
  subnet_ids         = var.subnet_ids
  lb_domain_name     = var.lb_domain_name
  lb_cert_domain     = var.lb_cert_domain
  availability_zones = var.availability_zones
  common_tags        = local.common_tags
}
