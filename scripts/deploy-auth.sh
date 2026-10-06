#!/usr/bin/env bash
# Create or update the Cognito stack. Google credentials come from the gitignored .env and reach
# CloudFormation only as a NoEcho parameter; they are never printed or written to the repository.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${AUTH_STACK:?}" "${AUTH_REGION:?}" "${SITE_URL:?}"
[[ -f .env ]] && { set -a; source .env; set +a; }
: "${COGNITO_DOMAIN_PREFIX:?Set COGNITO_DOMAIN_PREFIX in .env}"
: "${GOOGLE_CLIENT_ID:?Set GOOGLE_CLIENT_ID in .env}" "${GOOGLE_CLIENT_SECRET:?Set GOOGLE_CLIENT_SECRET in .env}"
[[ "$SITE_URL" == https://* ]] || { echo "Site URL must use HTTPS: $SITE_URL"; exit 1; }
# With a custom domain the CloudFront address serves the same site; allow sign-in from both.
ALTERNATE_URL="https://${CLOUDFRONT_DOMAIN:?}"
[[ "${ALTERNATE_URL%/}" == "${SITE_URL%/}" ]] && ALTERNATE_URL=
STATE=$(aws cloudformation describe-stacks --region "$AUTH_REGION" --stack-name "$AUTH_STACK" --query 'Stacks[0].StackStatus' --output text 2> /dev/null || true)
if [[ "$STATE" == ROLLBACK_COMPLETE ]]; then
  # A stack whose first create failed holds no resources and can only be deleted.
  aws cloudformation delete-stack --region "$AUTH_REGION" --stack-name "$AUTH_STACK"
  aws cloudformation wait stack-delete-complete --region "$AUTH_REGION" --stack-name "$AUTH_STACK"
fi
aws cloudformation deploy --region "$AUTH_REGION" --stack-name "$AUTH_STACK" \
  --template-file infra/auth.yml --no-fail-on-empty-changeset --tags PROJECT_NAME=spry \
  --parameter-overrides "SiteUrl=${SITE_URL%/}" "AlternateSiteUrl=$ALTERNATE_URL" "DomainPrefix=$COGNITO_DOMAIN_PREFIX" \
  "GoogleClientId=$GOOGLE_CLIENT_ID" "GoogleClientSecret=$GOOGLE_CLIENT_SECRET"
AWS_PAGER='' aws cloudformation describe-stacks --region "$AUTH_REGION" --stack-name "$AUTH_STACK" \
  --query 'Stacks[0].Outputs[].[OutputKey,OutputValue]' --output table
