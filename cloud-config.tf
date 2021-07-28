#############################################################################################################################
#
# Provider - AWS
#

provider "aws" {
  region  = "us-east-1"

  ## AWS Profile Master Account
  profile = "aws-profile-master"
}

terraform {
  backend "s3" {
    profile                     = "aws-profile-master"
    bucket                      = "s3-bucket-tfstate"
    key                         = "accounts/monitor-organizations/terraform.tfstate"
    region                      = "us-east-1"
    encrypt                     = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
  }
}

#############################################################################################################################
#
# Variavies de Input Global
#

locals {
  # Stack Name Global
  stack_name = "OrganizationsEvents"

  # Tag Resources
  default_tags = {
    SquadTeam       = "SRE"
    ApplicationRole = "Monitor Organizations"
  }
}