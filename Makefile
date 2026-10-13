.PHONY: up check deploy-frontend deploy-backend deploy-auth auth-env update-stack \
	deploy-reports check-week report-now report-local reports-ls report-logs
# Sign-in (Cognito) stack. CI passes AUTH_STACK from a repository variable; while that variable is
# empty the site is built without sign-in, exactly as in Lab 2.
AUTH_STACK ?= spry-auth
AUTH_REGION ?= us-east-1
MAIN_STACK := spry-lab
MAIN_REGION := eu-north-1
stack_output = aws cloudformation describe-stacks --region $(2) --stack-name $(1) --query "Stacks[0].Outputs[?OutputKey=='$(3)'].OutputValue" --output text
auth_output = $(call stack_output,$(AUTH_STACK),$(AUTH_REGION),$(1))
# Weekly report stack, next to spry-lab.
REPORTS_STACK ?= spry-reports
reports_output = $(call stack_output,$(REPORTS_STACK),$(MAIN_REGION),$(1))
up:
	docker compose up --build
check:
	cd backend && ruff check . && ruff format --check . && pytest
	cd frontend && npm ci && npm run lint && npm run format:check && npm run build
deploy-frontend:
	@set -e; if [ -n "$(AUTH_STACK)" ]; then \
	  VITE_COGNITO_AUTHORITY=$$($(call auth_output,Authority)); \
	  VITE_COGNITO_CLIENT_ID=$$($(call auth_output,ClientId)); \
	  VITE_COGNITO_DOMAIN=$$($(call auth_output,LoginDomain)); \
	  export VITE_COGNITO_AUTHORITY VITE_COGNITO_CLIENT_ID VITE_COGNITO_DOMAIN; \
	  echo "Sign-in: $$VITE_COGNITO_AUTHORITY"; \
	fi; bash scripts/deploy-frontend.sh
# PROTECT_API=1 makes the API require a Cognito access token (stretch goal); otherwise it stays public.
deploy-backend:
	@set -e; if [ "$(PROTECT_API)" = 1 ]; then \
	  COGNITO_REGION=$$($(call auth_output,Region)); \
	  COGNITO_USER_POOL_ID=$$($(call auth_output,UserPoolId)); \
	  COGNITO_CLIENT_ID=$$($(call auth_output,ClientId)); \
	  export COGNITO_REGION COGNITO_USER_POOL_ID COGNITO_CLIENT_ID; \
	  echo "API requires tokens from $$COGNITO_USER_POOL_ID"; \
	fi; bash scripts/deploy-backend.sh
deploy-auth:
	@SITE_URL=$$($(call stack_output,$(MAIN_STACK),$(MAIN_REGION),FrontendUrl)) \
	  CLOUDFRONT_DOMAIN=$$($(call stack_output,$(MAIN_STACK),$(MAIN_REGION),CloudFrontDnsName)) \
	  AUTH_STACK=$(AUTH_STACK) AUTH_REGION=$(AUTH_REGION) bash scripts/deploy-auth.sh
# Lines for .env, so that docker compose runs local sign-in against the same user pool.
auth-env:
	@echo "VITE_COGNITO_AUTHORITY=$$($(call auth_output,Authority))"
	@echo "VITE_COGNITO_CLIENT_ID=$$($(call auth_output,ClientId))"
	@echo "VITE_COGNITO_DOMAIN=$$($(call auth_output,LoginDomain))"
update-stack:
	bash scripts/aws-update-stack.sh
# Weekly report. SCHEDULE='rate(5 minutes)' for one test run, FAIL_WEEK=2026-W01 for the DLQ
# exercise; deploying again without them restores the Monday schedule and a working builder.
deploy-reports:
	REPORTS_STACK=$(REPORTS_STACK) SCHEDULE="$(SCHEDULE)" FAIL_WEEK="$(FAIL_WEEK)" bash scripts/deploy-reports.sh
check-week:
	@echo "$(WEEK)" | grep -Eq '^[0-9]{4}-W[0-9]{2}$$' || { echo "Usage: make $(MAKECMDGOALS) WEEK=2026-W40"; exit 1; }
# Rebuild one week's report on demand: the same command the schedule sends, with a fixed week.
report-now: check-week
	aws sqs send-message --region $(MAIN_REGION) --queue-url "$$($(call reports_output,QueueUrl))" \
	  --message-body '{"week": "$(WEEK)", "source": "manual"}' --query MessageId --output text
# The same report from the local compose database (docker compose up first).
report-local: check-week
	docker compose exec -T backend python -m app.reports.weekly $(WEEK)
reports-ls:
	aws s3 ls "s3://$$($(call reports_output,ReportsBucket))/reports/" --recursive --region $(MAIN_REGION)
# The "triggered" lines of both functions: which event started each run.
report-logs:
	@for output in BuilderLogGroup MailerLogGroup; do \
	  aws logs filter-log-events --region $(MAIN_REGION) --log-group-name "$$($(call reports_output,$$output))" \
	    --filter-pattern '"triggered"' --query 'events[].[timestamp,message]' --output text; \
	done
