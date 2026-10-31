.PHONY: up check deploy-frontend deploy-backend auth-env update-stack infra-init infra-plan \
	infra-output frontend-env check-week report-now report-local reports-ls report-logs llm-hello \
	parse parser-logs
MAIN_STACK := spry-lab
MAIN_REGION := eu-north-1
# Infrastructure from Lab 4 on (sign-in, weekly report, agenda parser, budget) is Terraform in
# infra/, applied by HCP Terraform (workspace spry-dev) after a merge to main. There is no apply
# here: from a laptop you only plan and read outputs (terraform login first).
TF := terraform -chdir=infra
tf_output = $(TF) output -raw $(1)
# Claude Opus 5.5 is the target; this account's Claude quota is 0 until AWS Support lifts it,
# so the deployed parser runs Amazon Nova Pro (parser_model in infra/terraform.tfvars).
PARSER_MODEL ?= us.amazon.nova-pro-v1:0
up:
	docker compose up --build
check:
	cd backend && ruff check . && ruff format --check . && pytest
	cd frontend && npm ci && npm run lint && npm run format:check && npm run build
# Sign-in and parser settings come from frontend/.env.production (make frontend-env), which Vite
# reads at build time; CI needs no access to Terraform.
deploy-frontend:
	bash scripts/deploy-frontend.sh
# PROTECT_API=1 makes the API require a Cognito access token (stretch goal); otherwise it stays public.
deploy-backend:
	@set -e; if [ "$(PROTECT_API)" = 1 ]; then \
	  AUTHORITY=$$(sed -n 's/^VITE_COGNITO_AUTHORITY=//p' frontend/.env.production); \
	  COGNITO_USER_POOL_ID=$${AUTHORITY##*/}; COGNITO_REGION=$${COGNITO_USER_POOL_ID%%_*}; \
	  COGNITO_CLIENT_ID=$$(sed -n 's/^VITE_COGNITO_CLIENT_ID=//p' frontend/.env.production); \
	  export COGNITO_REGION COGNITO_USER_POOL_ID COGNITO_CLIENT_ID; \
	  echo "API requires tokens from $$COGNITO_USER_POOL_ID"; \
	fi; bash scripts/deploy-backend.sh
# Lines for .env, so that docker compose runs local sign-in against the same user pool.
auth-env:
	@grep '^VITE_COGNITO_' frontend/.env.production
update-stack:
	bash scripts/aws-update-stack.sh
infra-init:
	$(TF) init -input=false
# A speculative plan: it runs in HCP Terraform on the files in your working copy and can never
# apply. Pull requests get the same plan as a check.
infra-plan: infra-init
	$(TF) plan
infra-output:
	@$(TF) output
# The public values the site build needs. Commit the file after the infrastructure changes.
frontend-env:
	@{ echo '# Written by make frontend-env from the Terraform outputs (public values only).'; \
	  echo "VITE_COGNITO_AUTHORITY=$$($(call tf_output,authority))"; \
	  echo "VITE_COGNITO_CLIENT_ID=$$($(call tf_output,client_id))"; \
	  echo "VITE_COGNITO_DOMAIN=$$($(call tf_output,login_domain))"; \
	  echo "VITE_PARSER_URL=$$($(call tf_output,parser_url))"; } > frontend/.env.production
	@cat frontend/.env.production
# Weekly report. For one test run set schedule_expression = "rate(5 minutes)", for the DLQ exercise
# fail_week = "2026-W01", in infra/terraform.tfvars, through a pull request like any other change.
check-week:
	@echo "$(WEEK)" | grep -Eq '^[0-9]{4}-W[0-9]{2}$$' || { echo "Usage: make $(MAKECMDGOALS) WEEK=2026-W40"; exit 1; }
# Rebuild one week's report on demand: the same command the schedule sends, with a fixed week.
report-now: check-week
	aws sqs send-message --region $(MAIN_REGION) --queue-url "$$($(call tf_output,queue_url))" \
	  --message-body '{"week": "$(WEEK)", "source": "manual"}' --query MessageId --output text
# The same report from the local compose database (docker compose up first).
report-local: check-week
	docker compose exec -T backend python -m app.reports.weekly $(WEEK)
reports-ls:
	aws s3 ls "s3://$$($(call tf_output,reports_bucket))/reports/" --recursive --region $(MAIN_REGION)
# The "triggered" lines of both functions: which event started each run.
report-logs:
	@for output in builder_log_group mailer_log_group; do \
	  aws logs filter-log-events --region $(MAIN_REGION) --log-group-name "$$($(call tf_output,$$output))" \
	    --filter-pattern '"triggered"' --query 'events[].[timestamp,message]' --output text; \
	done
# From your laptop with your AWS login: pip install -r backend/requirements.txt first.
llm-hello:
	cd backend && PARSER_MODEL=$(PARSER_MODEL) python3 -m app.ai.hello
# make parse TEXT="Пн 10:00, синк по прайсингу..." [TODAY=2026-10-26] [TZ=Europe/Kyiv]
parse:
	@test -n "$(TEXT)" || { echo 'Usage: make parse TEXT="..."'; exit 1; }
	cd backend && PARSER_MODEL=$(PARSER_MODEL) TODAY=$(TODAY) TZ=$(or $(TZ),Europe/Kyiv) \
	  python3 -m app.ai.agenda "$$TEXT"
# One JSON line per parse: user, model, prompt version, tokens, latency, cost.
parser-logs:
	aws logs filter-log-events --region $(MAIN_REGION) --log-group-name "$$($(call tf_output,parser_log_group))" \
	  --filter-pattern '{ $$.event = "agenda_*" }' --query 'events[].message' --output text
