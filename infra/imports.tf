# Adopting the resources that CloudFormation created (Lab 7, Part 2, Step 3). The IDs come from
# the stacks before they were deleted with DeletionPolicy Retain. Delete this file after the
# import has been applied.

# --- spry-auth (us-east-1) ---
import {
  to = aws_cognito_user_pool.main
  id = "us-east-1_7eKhzeJng"
}
import {
  to = aws_cognito_identity_provider.google
  id = "us-east-1_7eKhzeJng:Google"
}
import {
  to = aws_cognito_user_pool_client.web
  id = "us-east-1_7eKhzeJng/6pbf47lrqj9huqlj1c6hiues7v"
}
import {
  to = aws_cognito_user_pool_domain.main
  id = "spry-fourshrimp"
}
import {
  to = aws_cognito_managed_login_branding.web
  id = "us-east-1_7eKhzeJng,83aa6ee5-7539-4f17-a1d9-8fb0f37ca49b"
}

# --- spry-reports (eu-north-1) ---
import {
  to = aws_s3_bucket.reports
  id = "spry-reports-751501312355"
}
import {
  to = aws_s3_bucket_public_access_block.reports
  id = "spry-reports-751501312355"
}
import {
  to = aws_s3_bucket_ownership_controls.reports
  id = "spry-reports-751501312355"
}
import {
  to = aws_s3_bucket_server_side_encryption_configuration.reports
  id = "spry-reports-751501312355"
}
import {
  to = aws_s3_bucket_lifecycle_configuration.reports
  id = "spry-reports-751501312355"
}
import {
  to = aws_s3_bucket_policy.reports
  id = "spry-reports-751501312355"
}
import {
  to = aws_s3_bucket_notification.reports
  id = "spry-reports-751501312355"
}
import {
  to = aws_vpc_endpoint.s3
  id = "vpce-08f22f2eace7b072b"
}
import {
  to = aws_sqs_queue.report_requests_dlq
  id = "https://sqs.eu-north-1.amazonaws.com/751501312355/spry-report-requests-dlq"
}
import {
  to = aws_sqs_queue.report_requests
  id = "https://sqs.eu-north-1.amazonaws.com/751501312355/spry-report-requests"
}
import {
  to = aws_iam_role.scheduler
  id = "spry-reports-SchedulerRole-ZchjjWmzj3WV"
}
import {
  to = aws_iam_role_policy.scheduler
  id = "spry-reports-SchedulerRole-ZchjjWmzj3WV:send-report-request"
}
import {
  to = aws_scheduler_schedule.weekly
  id = "default/spry-weekly-report"
}
import {
  to = aws_cloudwatch_log_group.builder
  id = "/aws/lambda/spry-report-builder"
}
import {
  to = aws_iam_role.builder
  id = "spry-reports-BuilderRole-oVnLteSaUYGU"
}
import {
  to = aws_iam_role_policy_attachment.builder_vpc
  id = "spry-reports-BuilderRole-oVnLteSaUYGU/arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}
import {
  to = aws_iam_role_policy.builder
  id = "spry-reports-BuilderRole-oVnLteSaUYGU:build-reports"
}
import {
  to = aws_lambda_function.builder
  id = "spry-report-builder"
}
import {
  to = aws_lambda_event_source_mapping.builder_queue
  id = "acbf7d58-0e7a-4528-8429-1afdb9a6713b"
}
import {
  to = aws_cloudwatch_log_group.mailer
  id = "/aws/lambda/spry-report-mailer"
}
import {
  to = aws_iam_role.mailer
  id = "spry-reports-MailerRole-WWb3nFwFds0W"
}
import {
  to = aws_iam_role_policy_attachment.mailer_logs
  id = "spry-reports-MailerRole-WWb3nFwFds0W/arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
import {
  to = aws_iam_role_policy.mailer
  id = "spry-reports-MailerRole-WWb3nFwFds0W:mail-reports"
}
import {
  to = aws_lambda_function.mailer
  id = "spry-report-mailer"
}
import {
  to = aws_lambda_permission.mailer_s3
  id = "spry-report-mailer/spry-reports-MailerInvokePermission-k1teifiz40MQ"
}
import {
  to = aws_sesv2_email_identity.domain
  id = "antonyivaso.dynv6.net"
}
import {
  to = aws_sesv2_email_identity_mail_from_attributes.domain
  id = "antonyivaso.dynv6.net"
}
import {
  to = aws_sesv2_email_identity.recipient
  id = "antonenko.pn@ucu.edu.ua"
}

# --- spry-ai (eu-north-1) and spry-ai-budget (us-east-1) ---
import {
  to = aws_cloudwatch_log_group.parser
  id = "/aws/lambda/spry-agenda-parser"
}
import {
  to = aws_iam_role.parser
  id = "spry-ai-ParserRole-3CPWvMsU3CnN"
}
import {
  to = aws_iam_role_policy_attachment.parser_logs
  id = "spry-ai-ParserRole-3CPWvMsU3CnN/arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
import {
  to = aws_iam_role_policy.parser
  id = "spry-ai-ParserRole-3CPWvMsU3CnN:call-claude"
}
import {
  to = aws_lambda_function.parser
  id = "spry-agenda-parser"
}
import {
  to = aws_lambda_function_url.parser
  id = "spry-agenda-parser"
}
import {
  to = aws_lambda_permission.parser_url
  id = "spry-agenda-parser/spry-ai-ParserUrlPermission-km4ubhlCPcKe"
}
import {
  to = aws_lambda_permission.parser_invoke
  id = "spry-agenda-parser/spry-ai-ParserInvokePermission-IRDDaJ8nBfVz"
}
import {
  to = aws_budgets_budget.monthly
  id = "751501312355:spry-monthly"
}
