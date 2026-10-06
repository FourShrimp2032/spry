.PHONY: up check deploy-frontend deploy-backend deploy-auth auth-env update-stack
# Sign-in (Cognito) stack. CI passes AUTH_STACK from a repository variable; while that variable is
# empty the site is built without sign-in, exactly as in Lab 2.
AUTH_STACK ?= spry-auth
AUTH_REGION ?= us-east-1
MAIN_STACK := spry-lab
MAIN_REGION := eu-north-1
stack_output = aws cloudformation describe-stacks --region $(2) --stack-name $(1) --query "Stacks[0].Outputs[?OutputKey=='$(3)'].OutputValue" --output text
auth_output = $(call stack_output,$(AUTH_STACK),$(AUTH_REGION),$(1))
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
