# The one piece that has to exist before HCP Terraform can do anything: the IAM OIDC provider
# for app.terraform.io and the role that the spry-dev workspace's runs assume. Applied once from
# a laptop with the owner's credentials (workspace spry-bootstrap, Local execution mode: the state
# is in HCP Terraform, the run is on the laptop).

terraform {
  required_version = ">= 1.10"

  cloud {
    organization = "ooad-fourshrimp2032"

    workspaces {
      name = "spry-bootstrap"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = "eu-north-1"

  default_tags {
    tags = {
      PROJECT_NAME = "spry"
      ManagedBy    = "terraform"
    }
  }
}

variable "tfc_organization" {
  type    = string
  default = "ooad-fourshrimp2032"
}

variable "tfc_workspace" {
  type    = string
  default = "spry-dev"
}

data "tls_certificate" "tfc" {
  url = "https://app.terraform.io"
}

resource "aws_iam_openid_connect_provider" "tfc" {
  url             = "https://app.terraform.io"
  client_id_list  = ["aws.workload.identity"]
  thumbprint_list = [data.tls_certificate.tfc.certificates[0].sha1_fingerprint]
}

resource "aws_iam_role" "tfc" {
  name = "hcp-terraform-${var.tfc_organization}"

  # Only runs of one workspace of one organization, plan and apply phases.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.tfc.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = { "app.terraform.io:aud" = "aws.workload.identity" }
        StringLike = {
          "app.terraform.io:sub" = "organization:${var.tfc_organization}:project:*:workspace:${var.tfc_workspace}:run_phase:*"
        }
      }
    }]
  })
}

# For the class project. A real team narrows this to the services the workspace manages.
resource "aws_iam_role_policy_attachment" "tfc" {
  role       = aws_iam_role.tfc.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

output "role_arn" {
  value = aws_iam_role.tfc.arn
}
