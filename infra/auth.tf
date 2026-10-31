# Sign-in (Lab 4, was infra/auth.yml): Cognito user pool with email + password and Google, a
# public app client for the browser, and a managed login (v2) domain. Essentials tier: the first
# 10,000 monthly active users are free.

# The site's addresses come from the course stack, which stays in CloudFormation.
data "aws_cloudformation_stack" "main" {
  name = var.main_stack
}

locals {
  site_url = trimsuffix(data.aws_cloudformation_stack.main.outputs["FrontendUrl"], "/")
  # With a custom domain the CloudFront address serves the same site; allow sign-in from both.
  cloudfront_url = "https://${data.aws_cloudformation_stack.main.outputs["CloudFrontDnsName"]}"
  site_urls      = distinct([local.site_url, local.cloudfront_url, var.local_url])
}

resource "aws_cognito_user_pool" "main" {
  provider = aws.us_east_1

  name           = "${var.project_name}-users"
  user_pool_tier = "ESSENTIALS"

  # Sign in with an email, not a separate username; Cognito emails a code to confirm it.
  # username_attributes forces replacement: changing it would delete every account.
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  username_configuration {
    case_sensitive = false
  }

  admin_create_user_config {
    allow_admin_create_user_only = false
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  password_policy {
    minimum_length                   = 10
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = false
    temporary_password_validity_days = 7
  }

  # Cognito's built-in sender: about 50 emails a day per account. A real product uses SES.
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  # The users from Lab 4 live here. A plan that would replace the pool fails instead.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_cognito_identity_provider" "google" {
  provider = aws.us_east_1

  user_pool_id  = aws_cognito_user_pool.main.id
  provider_name = "Google"
  provider_type = "Google"

  provider_details = {
    client_id        = var.google_client_id
    client_secret    = var.google_client_secret
    authorize_scopes = "openid email profile"
    # Cognito fills these in for a Google provider; written out so that the plan stays empty.
    attributes_url                = "https://people.googleapis.com/v1/people/me?personFields="
    attributes_url_add_attributes = "true"
    authorize_url                 = "https://accounts.google.com/o/oauth2/v2/auth"
    oidc_issuer                   = "https://accounts.google.com"
    token_request_method          = "POST"
    token_url                     = "https://www.googleapis.com/oauth2/v4/token"
  }

  # Without this a Google user arrives with no email and the header has nothing to show.
  attribute_mapping = {
    email          = "email"
    email_verified = "email_verified"
    name           = "name"
    username       = "sub"
  }
}

# Public client: a browser cannot keep a secret, so PKCE protects the code exchange instead.
resource "aws_cognito_user_pool_client" "web" {
  provider = aws.us_east_1

  # No generate_secret: false is the default, and an imported client has no value for it, so
  # writing it out would force a replacement (a new client ID breaks every sign-in).
  name                                 = "${var.project_name}-web"
  user_pool_id                         = aws_cognito_user_pool.main.id
  explicit_auth_flows                  = ["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
  prevent_user_existence_errors        = "ENABLED"
  enable_token_revocation              = true
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  # The reference, not the string "Google": the client must wait for the provider to exist.
  supported_identity_providers = ["COGNITO", aws_cognito_identity_provider.google.provider_name]

  # Exact matches, trailing slash included: the app builds these from window.location.origin.
  callback_urls = [for url in local.site_urls : "${url}/auth/callback/"]
  logout_urls   = [for url in local.site_urls : "${url}/"]
}

resource "aws_cognito_user_pool_domain" "main" {
  provider = aws.us_east_1

  domain                = var.cognito_domain_prefix
  user_pool_id          = aws_cognito_user_pool.main.id
  managed_login_version = 2
}

# A version 2 domain has no sign-in page until the client has a branding style.
resource "aws_cognito_managed_login_branding" "web" {
  provider = aws.us_east_1

  user_pool_id                = aws_cognito_user_pool.main.id
  client_id                   = aws_cognito_user_pool_client.web.id
  use_cognito_provided_values = true

  depends_on = [aws_cognito_user_pool_domain.main]
}
