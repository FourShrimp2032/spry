# Everything the Makefile and the frontend build read: terraform output -raw <name>.

# --- Sign-in ---

output "user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "client_id" {
  value = aws_cognito_user_pool_client.web.id
}

output "cognito_region" {
  value = "us-east-1"
}

output "authority" {
  description = "OIDC issuer; its JWKS is at <authority>/.well-known/jwks.json"
  value       = "https://cognito-idp.us-east-1.amazonaws.com/${aws_cognito_user_pool.main.id}"
}

output "login_domain" {
  description = "Managed login domain; /logout lives here (Cognito has no OIDC end-session endpoint)"
  value       = "https://${aws_cognito_user_pool_domain.main.domain}.auth.us-east-1.amazoncognito.com"
}

output "google_redirect_uri" {
  description = "Authorised redirect URI for the Google OAuth client"
  value       = "https://${aws_cognito_user_pool_domain.main.domain}.auth.us-east-1.amazoncognito.com/oauth2/idpresponse"
}

# --- Weekly report ---

output "reports_bucket" {
  value = aws_s3_bucket.reports.bucket
}

output "queue_url" {
  value = aws_sqs_queue.report_requests.url
}

output "dlq_url" {
  value = aws_sqs_queue.report_requests_dlq.url
}

output "builder_function" {
  value = aws_lambda_function.builder.function_name
}

output "mailer_function" {
  value = aws_lambda_function.mailer.function_name
}

output "builder_log_group" {
  value = aws_cloudwatch_log_group.builder.name
}

output "mailer_log_group" {
  value = aws_cloudwatch_log_group.mailer.name
}

output "sender" {
  value = "reports@${var.mail_domain}"
}

output "dns_records" {
  description = "Records to keep at the DNS provider: DKIM, MAIL FROM (MX + SPF) and DMARC"
  value = concat(
    [for token in aws_sesv2_email_identity.domain.dkim_signing_attributes[0].tokens :
    "${token}._domainkey.${var.mail_domain} CNAME ${token}.dkim.amazonses.com."],
    [
      "mail.${var.mail_domain} MX 10 feedback-smtp.${var.region}.amazonses.com",
      "mail.${var.mail_domain} TXT \"v=spf1 include:amazonses.com ~all\"",
      "_dmarc.${var.mail_domain} TXT \"v=DMARC1; p=none;\"",
    ],
  )
}

# --- Paste an agenda ---

output "parser_url" {
  value = trimsuffix(aws_lambda_function_url.parser.function_url, "/")
}

output "parser_function" {
  value = aws_lambda_function.parser.function_name
}

output "parser_log_group" {
  value = aws_cloudwatch_log_group.parser.name
}

output "parser_model" {
  value = var.parser_model
}
