#!/usr/bin/env bash
# Create or update the agenda parser stack. The image is the one the ECS service runs; Cognito
# comes from the auth stack, the site's origins from spry-lab. Writes the parser URL into
# frontend/.env.production, which the site build (CI included) reads.
set -euo pipefail
cd "$(dirname "$0")/.."
export AWS_REGION=eu-north-1 AWS_PAGER=''
: "${AI_STACK:?}" "${AUTH_STACK:?}" "${AUTH_REGION:?}"
[[ -f .env ]] && { set -a; source .env; set +a; }
BUDGET_EMAIL=${BUDGET_EMAIL:-${REPORT_RECIPIENTS%%,*}}
: "${BUDGET_EMAIL:?Set BUDGET_EMAIL in .env}"
output() { aws cloudformation describe-stacks --region "$2" --stack-name "$1" --query "Stacks[0].Outputs[?OutputKey=='$3'].OutputValue" --output text; }

CLUSTER=$(output spry-lab "$AWS_REGION" EcsCluster)
SERVICE=$(output spry-lab "$AWS_REGION" EcsService)
TASK_DEF=$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" --query 'services[0].taskDefinition' --output text)
IMAGE=$(aws ecs describe-task-definition --task-definition "$TASK_DEF" --query 'taskDefinition.containerDefinitions[?name==`backend`].image | [0]' --output text)
# The image must contain the parser, i.e. be built from a commit that has it.
TAG=${IMAGE##*:}
PARSER_COMMIT=$(git log -1 --format=%H -- backend/app/ai/agenda_lambda.py)
if ! git merge-base --is-ancestor "$PARSER_COMMIT" "$TAG" 2> /dev/null; then
  echo "The ECS service runs $TAG, which does not include the parser."
  echo "Push to main, wait for the deploy job to finish, then run this again."
  exit 1
fi

ORIGINS="$(output spry-lab "$AWS_REGION" FrontendUrl),https://$(output spry-lab "$AWS_REGION" CloudFrontDnsName),http://localhost:5173"
ORIGINS=$(tr ',' '\n' <<< "$ORIGINS" | sed 's#/$##' | sort -u | paste -sd, -)

STATE=$(aws cloudformation describe-stacks --stack-name "$AI_STACK" --query 'Stacks[0].StackStatus' --output text 2> /dev/null || true)
if [[ "$STATE" == ROLLBACK_COMPLETE ]]; then
  # A stack whose first create failed holds no resources and can only be deleted.
  aws cloudformation delete-stack --stack-name "$AI_STACK"
  aws cloudformation wait stack-delete-complete --stack-name "$AI_STACK"
fi
echo "Parser image: $IMAGE"
echo "Origins: $ORIGINS"
aws cloudformation deploy --stack-name "$AI_STACK" --template-file infra/ai.yml \
  --capabilities CAPABILITY_IAM --no-fail-on-empty-changeset --tags PROJECT_NAME=spry \
  --parameter-overrides "BackendImage=$IMAGE" "ParserModel=${PARSER_MODEL:-anthropic.claude-opus-5-5}" \
  "CognitoRegion=$AUTH_REGION" "CognitoUserPoolId=$(output "$AUTH_STACK" "$AUTH_REGION" UserPoolId)" \
  "CognitoClientId=$(output "$AUTH_STACK" "$AUTH_REGION" ClientId)" "AllowedOrigins=$ORIGINS"
# CloudFormation supports budgets only in us-east-1.
aws cloudformation deploy --region us-east-1 --stack-name "$AI_STACK-budget" \
  --template-file infra/budget.yml --no-fail-on-empty-changeset --tags PROJECT_NAME=spry \
  --parameter-overrides "BudgetEmail=$BUDGET_EMAIL" "BudgetAmount=${BUDGET_AMOUNT:-5}"
URL=$(output "$AI_STACK" "$AWS_REGION" ParserUrl)
printf '# Written by scripts/deploy-ai.sh: the agenda parser (a public, token-protected URL).\nVITE_PARSER_URL=%s\n' "${URL%/}" > frontend/.env.production
aws cloudformation describe-stacks --stack-name "$AI_STACK" --query 'Stacks[0].Outputs[].[OutputKey,OutputValue]' --output table
