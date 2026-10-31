terraform {
  required_version = ">= 1.10"

  # State, locking and runs live in HCP Terraform. The workspace runs plan on every pull request
  # and apply on every merge to main, with dynamic AWS credentials (infra/bootstrap).
  cloud {
    organization = "ooad-fourshrimp2032"

    workspaces {
      name = "spry-dev"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
  }
}

# eu-north-1: everything next to spry-lab (reports, parser).
provider "aws" {
  region = var.region

  default_tags {
    tags = local.tags
  }
}

# Cognito lives in us-east-1 since Lab 4, and so does the budget.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = local.tags
  }
}

locals {
  tags = {
    PROJECT_NAME = var.project_name
    ManagedBy    = "terraform"
  }
}
