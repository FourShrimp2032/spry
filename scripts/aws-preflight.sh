#!/usr/bin/env bash
# Read-only. Safe to run before deciding whether to create billable resources.
set -euo pipefail
export AWS_REGION=eu-north-1 AWS_PAGER=''
printf 'AWS identity (never contains access keys):\n'
aws sts get-caller-identity
printf '\nExisting GitHub OIDC provider (reuse if present):\n'
aws iam list-open-id-connect-providers --query "OpenIDConnectProviderList[?ends_with(Arn, '/token.actions.githubusercontent.com')].Arn" --output json
printf '\nAvailable PostgreSQL 16 minor versions for db.t4g.micro:\n'
aws rds describe-orderable-db-instance-options --engine postgres --db-instance-class db.t4g.micro --region "$AWS_REGION" --query 'OrderableDBInstanceOptions[?starts_with(EngineVersion, `16.`)].EngineVersion' --output json
printf '\nExisting Spry stack (empty means none):\n'
aws cloudformation list-stacks --region "$AWS_REGION" --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE CREATE_IN_PROGRESS UPDATE_IN_PROGRESS ROLLBACK_COMPLETE --query 'StackSummaries[?StackName==`spry-lab`].[StackName,StackStatus]' --output json
printf '\nFargate On-Demand vCPU quota:\n'
aws service-quotas get-service-quota --service-code fargate --quota-code L-3032A538 --region "$AWS_REGION" --query 'Quota.Value' --output text
