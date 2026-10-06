#!/usr/bin/env bash
# Run by the owner (CloudShell or an admin profile) to add the Lab 3 sign-in changes to spry-lab.
# Starts from the template that is actually deployed (it may differ from infra/aws-stack.json),
# keeps every current parameter value, shows the change set and refuses unexpected changes.
set -euo pipefail
export AWS_REGION=eu-north-1 AWS_PAGER=''
cd "$(dirname "$0")/.."
STACK=spry-lab
# The Cognito update touches only these; anything else (database, ECS service) needs a review first.
EXPECTED='Distribution GitHubDeployRole SpaRouteFunction'
CHANGE_SET="update-$(date +%Y%m%d%H%M%S)"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
aws cloudformation get-template --stack-name "$STACK" --template-stage Original --query TemplateBody --output json > "$WORK/deployed.json"
python3 scripts/add-sign-in-routes.py "$WORK/deployed.json" "$WORK/updated.json"
# Copies for the repository: the deployed template before and after this change.
cp "$WORK/deployed.json" ~/spry-lab-deployed.json
cp "$WORK/updated.json" ~/spry-lab-updated.json
# CloudFormation accepts at most 51,200 bytes inline, so upload a compact copy.
python3 -c 'import json,sys; json.dump(json.load(open(sys.argv[1])), open(sys.argv[2], "w"), separators=(",", ":"))' "$WORK/updated.json" "$WORK/body.json"
aws cloudformation validate-template --template-body "file://$WORK/body.json" > /dev/null
PARAMS=()
for key in $(aws cloudformation describe-stacks --stack-name "$STACK" --query 'Stacks[0].Parameters[].ParameterKey' --output text); do
  PARAMS+=("ParameterKey=$key,UsePreviousValue=true")
done
aws cloudformation create-change-set --stack-name "$STACK" --change-set-name "$CHANGE_SET" \
  --template-body "file://$WORK/body.json" --capabilities CAPABILITY_IAM --parameters "${PARAMS[@]}" > /dev/null
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
