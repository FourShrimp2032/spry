#!/usr/bin/env bash
# Run by the owner (CloudShell or an admin profile) to apply infra/aws-stack.json to spry-lab.
# Keeps every current parameter value, shows the change set and refuses unexpected changes.
set -euo pipefail
export AWS_REGION=eu-north-1 AWS_PAGER=''
cd "$(dirname "$0")/.."
STACK=spry-lab
# The Cognito update touches only these; anything else (database, ECS service) needs a review first.
EXPECTED='Distribution GitHubDeployRole SpaRouteFunction'
CHANGE_SET="update-$(date +%Y%m%d%H%M%S)"
aws cloudformation validate-template --template-body file://infra/aws-stack.json > /dev/null
PARAMS=()
for key in $(aws cloudformation describe-stacks --stack-name "$STACK" --query 'Stacks[0].Parameters[].ParameterKey' --output text); do
  PARAMS+=("ParameterKey=$key,UsePreviousValue=true")
done
aws cloudformation create-change-set --stack-name "$STACK" --change-set-name "$CHANGE_SET" \
  --template-body file://infra/aws-stack.json --capabilities CAPABILITY_IAM --parameters "${PARAMS[@]}" > /dev/null
if ! aws cloudformation wait change-set-create-complete --stack-name "$STACK" --change-set-name "$CHANGE_SET"; then
  aws cloudformation describe-change-set --stack-name "$STACK" --change-set-name "$CHANGE_SET" --query StatusReason --output text
  aws cloudformation delete-change-set --stack-name "$STACK" --change-set-name "$CHANGE_SET"
  exit 1
fi
aws cloudformation describe-change-set --stack-name "$STACK" --change-set-name "$CHANGE_SET" \
  --query 'Changes[].ResourceChange.[Action,LogicalResourceId,ResourceType,Replacement]' --output table
for resource in $(aws cloudformation describe-change-set --stack-name "$STACK" --change-set-name "$CHANGE_SET" --query 'Changes[].ResourceChange.LogicalResourceId' --output text); do
  if [[ " $EXPECTED " != *" $resource "* ]]; then
    echo "Unexpected change to $resource. Nothing was applied; the change set is deleted."
    aws cloudformation delete-change-set --stack-name "$STACK" --change-set-name "$CHANGE_SET"
    exit 1
  fi
done
read -r -p "Apply these changes to $STACK? [y/N] " answer
if [[ "$answer" != y ]]; then
  aws cloudformation delete-change-set --stack-name "$STACK" --change-set-name "$CHANGE_SET"
  echo 'Cancelled; nothing changed.'
  exit 0
fi
aws cloudformation execute-change-set --stack-name "$STACK" --change-set-name "$CHANGE_SET"
aws cloudformation wait stack-update-complete --stack-name "$STACK"
echo "$STACK updated. CloudFront takes a few minutes to deploy the new route function."
