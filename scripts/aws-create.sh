#!/usr/bin/env bash
# Run by the user in AWS CloudShell after reviewing the resource/cost summary.
set -euo pipefail
export AWS_REGION=eu-north-1 AWS_PAGER=''
cd "$(dirname "$0")/.."
STACK_STATE=$(aws cloudformation list-stacks --region "$AWS_REGION" --query 'StackSummaries[?StackName==`spry-lab` && StackStatus!=`DELETE_COMPLETE`].StackStatus | [0]' --output text)
[[ "$STACK_STATE" == None ]] || { echo "Stack spry-lab already exists ($STACK_STATE). Stop and inspect it; do not overwrite an active deployment."; exit 1; }
OIDC_ARN=$(aws iam list-open-id-connect-providers --query "OpenIDConnectProviderList[?ends_with(Arn, '/token.actions.githubusercontent.com')].Arn | [0]" --output text)
[[ "$OIDC_ARN" != None ]] || OIDC_ARN=''
DB_VERSION=$(aws rds describe-orderable-db-instance-options --engine postgres --db-instance-class db.t4g.micro --query 'OrderableDBInstanceOptions[?starts_with(EngineVersion, `16.`)].EngineVersion' --output json | python3 -c 'import json,re,sys; versions=json.load(sys.stdin); print(max(versions,key=lambda s:tuple(map(int,re.findall(r"\d+",s)))) if versions else "")')
[[ -n "$DB_VERSION" ]] || { echo 'PostgreSQL 16 on db.t4g.micro is unavailable in this account/region'; exit 1; }
aws cloudformation validate-template --template-body file://infra/aws-stack.json > /dev/null
aws cloudformation create-stack --stack-name spry-lab --template-body file://infra/aws-stack.json --capabilities CAPABILITY_IAM --parameters "ParameterKey=ExistingGitHubOidcArn,ParameterValue=$OIDC_ARN" "ParameterKey=DatabaseEngineVersion,ParameterValue=$DB_VERSION" --tags Key=Project,Value=spry
printf '\nCreation started. View CloudFormation > spry-lab > Events. Wait for CREATE_COMPLETE, then run bash scripts/aws-outputs.sh.\n'
