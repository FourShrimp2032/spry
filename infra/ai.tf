# Paste an agenda (Lab 6, was infra/ai.yml and infra/budget.yml): the agenda-parser Lambda
# (backend image, outside the VPC, no database) behind a public function URL that requires a
# Cognito access token. It calls Claude (Anthropic Messages API) or Amazon Nova (Converse API) on
# Bedrock and returns JSON; saving goes through the main API.

locals {
  # The site's origins that may call the parser from the browser.
  parser_origins = sort(local.site_urls)
}

resource "aws_cloudwatch_log_group" "parser" {
  name              = "/aws/lambda/${var.project_name}-agenda-parser"
  retention_in_days = 30
}

resource "aws_iam_role" "parser" {
  name               = "spry-ai-ParserRole-3CPWvMsU3CnN"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "parser_logs" {
  role       = aws_iam_role.parser.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "parser" {
  name = "call-claude"
  role = aws_iam_role.parser.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # No API key to store or leak: the role is allowed to call the model, as it would be
      # allowed to write to S3. "*" for now; narrowing it is a discussion question.
      {
        Effect   = "Allow"
        Action   = "bedrock-mantle:CreateInference"
        Resource = "*"
      },
      # Converse (Amazon Nova through a US cross-region inference profile).
      {
        Effect   = "Allow"
        Action   = "bedrock:InvokeModel"
        Resource = "*"
      },
    ]
  })
}

# The backend image with another entry point, as report-builder. No VPC: the parser needs no
# database, reaches Bedrock and Cognito's keys over the internet, and costs nothing while idle.
resource "aws_lambda_function" "parser" {
  function_name = "${var.project_name}-agenda-parser"
  package_type  = "Image"
  image_uri     = var.backend_image
  architectures = ["x86_64"]
  role          = aws_iam_role.parser.arn
  timeout       = 30
  memory_size   = 512

  image_config {
    entry_point       = ["python", "-m", "awslambdaric"]
    command           = ["app.ai.agenda_lambda.handler"]
    working_directory = "/app"
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.parser.name
  }

  environment {
    variables = {
      PARSER_MODEL         = var.parser_model
      BEDROCK_REGION       = var.bedrock_region
      COGNITO_REGION       = "us-east-1"
      COGNITO_USER_POOL_ID = aws_cognito_user_pool.main.id
      COGNITO_CLIENT_ID    = aws_cognito_user_pool_client.web.id
    }
  }

  depends_on = [aws_iam_role_policy_attachment.parser_logs, aws_iam_role_policy.parser]
}

# Public URL, private wallet: the handler rejects every request without a valid Cognito access
# token (401) and every text over 10,000 characters (413) before calling the model.
resource "aws_lambda_function_url" "parser" {
  function_name      = aws_lambda_function.parser.function_name
  authorization_type = "NONE"

  cors {
    allow_origins = local.parser_origins
    allow_methods = ["POST"]
    allow_headers = ["authorization", "content-type"]
    max_age       = 3600
  }
}

# A function URL with authorization NONE needs both permissions to be reachable.
resource "aws_lambda_permission" "parser_url" {
  statement_id           = "spry-ai-ParserUrlPermission-km4ubhlCPcKe"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.parser.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

resource "aws_lambda_permission" "parser_invoke" {
  statement_id             = "spry-ai-ParserInvokePermission-IRDDaJ8nBfVz"
  action                   = "lambda:InvokeFunction"
  function_name            = aws_lambda_function.parser.function_name
  principal                = "*"
  invoked_via_function_url = true
}

# The cheapest insurance in the course: an email when the month's actual or forecast spend on
# this account passes the limit. The budget covers the whole account.
resource "aws_budgets_budget" "monthly" {
  provider = aws.us_east_1

  name         = "${var.project_name}-monthly"
  budget_type  = "COST"
  time_unit    = "MONTHLY"
  limit_amount = format("%.1f", var.budget_amount)
  limit_unit   = "USD"

  dynamic "notification" {
    for_each = ["ACTUAL", "FORECASTED"]

    content {
      notification_type          = notification.value
      comparison_operator        = "GREATER_THAN"
      threshold                  = 100
      threshold_type             = "PERCENTAGE"
      subscriber_email_addresses = [var.budget_email]
    }
  }
}
