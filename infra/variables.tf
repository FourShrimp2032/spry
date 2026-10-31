# Non-secret values are in terraform.tfvars. The one secret, google_client_secret, is a
# sensitive Terraform variable in the HCP Terraform workspace.

variable "project_name" {
  type    = string
  default = "spry"
}

variable "region" {
  type    = string
  default = "eu-north-1"
}

# The course template's stack (network, API, database, site) stays in CloudFormation;
# Terraform reads its outputs.
variable "main_stack" {
  type    = string
  default = "spry-lab"
}

# --- Sign-in (was infra/auth.yml) ------------------------------------------------------------

variable "cognito_domain_prefix" {
  type        = string
  description = "https://<prefix>.auth.us-east-1.amazoncognito.com. Google's OAuth client points here."

  validation {
    condition     = can(regex("^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$", var.cognito_domain_prefix))
    error_message = "Lowercase letters, digits and hyphens, at most 63 characters."
  }
}

variable "local_url" {
  type    = string
  default = "http://localhost:5173"
}

variable "google_client_id" {
  type = string

  validation {
    condition     = endswith(var.google_client_id, ".apps.googleusercontent.com")
    error_message = "A Google OAuth client ID ends in .apps.googleusercontent.com."
  }
}

variable "google_client_secret" {
  type      = string
  sensitive = true
}

# --- Backend image (report-builder and agenda-parser) ----------------------------------------

variable "backend_image" {
  type        = string
  description = "The backend image (ECR URI with the commit SHA tag) that the two image Lambdas run"
}

# --- Weekly report (was infra/reports.yml) ---------------------------------------------------

variable "private_subnet_ids" {
  type        = list(string)
  description = "Subnets with no route to the internet (the database subnets): the builder runs here"
}

variable "private_route_table_ids" {
  type        = list(string)
  description = "Route tables of those subnets; the S3 gateway endpoint is added to them"
}

variable "db_host" {
  type = string
}

variable "db_name" {
  type    = string
  default = "spry"
}

variable "db_user" {
  type = string
}

variable "db_secret_arn" {
  type        = string
  description = "Secrets Manager secret with a \"password\" key (the one the ECS task uses)"
}

variable "mail_domain" {
  type        = string
  description = "Domain verified in SES with DKIM; the report comes from reports@<domain>"
}

variable "recipients" {
  type        = list(string)
  description = "Report recipients. In the SES sandbox each one must be a verified identity."
}

variable "schedule_expression" {
  type        = string
  default     = "cron(0 7 ? * MON *)"
  description = "rate(5 minutes) for one test run, then back to the default"
}

variable "fail_week" {
  type        = string
  default     = ""
  description = "Lab 5 exercise only. The builder raises for this ISO week, to fill the DLQ."

  validation {
    condition     = can(regex("^([0-9]{4}-W[0-9]{2})?$", var.fail_week))
    error_message = "Empty, or an ISO week such as 2026-W01."
  }
}

# --- Paste an agenda (was infra/ai.yml and infra/budget.yml) ---------------------------------

variable "parser_model" {
  type        = string
  default     = "anthropic.claude-opus-5-5"
  description = "anthropic.* uses the Messages API; others (us.amazon.nova-pro-v1:0) Converse"
}

variable "bedrock_region" {
  type    = string
  default = "us-east-1"
}

variable "budget_email" {
  type = string
}

variable "budget_amount" {
  type    = number
  default = 5
}
