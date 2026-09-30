#!/usr/bin/env bash
# Share this JSON with the assistant; it contains resource identifiers, not secrets.
set -euo pipefail
AWS_PAGER='' aws cloudformation describe-stacks --stack-name spry-lab --region eu-north-1 --query 'Stacks[0].Outputs' --output json
