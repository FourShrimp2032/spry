#!/usr/bin/env bash
# Create or update the weekly report stack next to spry-lab. Everything the builder needs (image,
# database, network) is read from the running ECS service, so the function sees exactly what the
# API sees. Mail settings come from the gitignored .env.
set -euo pipefail
cd "$(dirname "$0")/.."
export AWS_REGION=eu-north-1 AWS_PAGER=''
MAIN_STACK=spry-lab
: "${REPORTS_STACK:?}"
[[ -f .env ]] && { set -a; source .env; set +a; }
: "${REPORT_MAIL_DOMAIN:?Set REPORT_MAIL_DOMAIN in .env, e.g. antonyivaso.dynv6.net}"
: "${REPORT_RECIPIENTS:?Set REPORT_RECIPIENTS in .env: your own email address}"
output() { aws cloudformation describe-stacks --stack-name "$MAIN_STACK" --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text; }

CLUSTER=$(output EcsCluster)
SERVICE=$(output EcsService)
SECURITY_GROUP=$(output EcsSecurityGroup)
TASK_DEF=$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" --query 'services[0].taskDefinition' --output text)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
aws ecs describe-task-definition --task-definition "$TASK_DEF" --query 'taskDefinition.containerDefinitions[?name==`backend`] | [0]' > "$WORK/container.json"
eval "$(python3 - "$WORK/container.json" <<'PYCODE'
import json, shlex, sys
c = json.load(open(sys.argv[1]))
env = {e["name"]: e["value"] for e in c.get("environment", [])}
secret = next(s["valueFrom"] for s in c.get("secrets", []) if s["name"] == "DB_PASSWORD")
values = {
    "IMAGE": c["image"],
    "DB_HOST": env["DB_HOST"],
    "DB_NAME": env.get("DB_NAME", "spry"),
    "DB_USER": env["DB_USER"],
    # ECS references the key as <secret ARN>:password::
    "DB_SECRET_ARN": secret.removesuffix(":password::"),
}
for name, value in values.items():
    print(f"{name}={shlex.quote(value)}")
PYCODE
)"

# The image must contain awslambdaric, i.e. be built from a commit that has the report code.
TAG=${IMAGE##*:}
REPORT_COMMIT=$(git log -1 --format=%H -- backend/app/reports/lambda_handler.py)
if ! git merge-base --is-ancestor "$REPORT_COMMIT" "$TAG" 2> /dev/null; then
  echo "The ECS service runs $TAG, which does not include the report code."
  echo "Push to main, wait for the deploy job to finish, then run this again."
  exit 1
fi

VPC=$(aws ec2 describe-security-groups --group-ids "$SECURITY_GROUP" --query 'SecurityGroups[0].VpcId' --output text)
# Private subnets: the ones that do not hand out public IPs (the database lives there).
SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC" "Name=map-public-ip-on-launch,Values=false" --query 'Subnets[].SubnetId' --output text | tr '\t' ',')
[[ -n "$SUBNETS" ]] || { echo "No private subnets in $VPC"; exit 1; }
# Their route tables: an explicit association, otherwise the VPC's main table.
ROUTE_TABLES=()
for subnet in ${SUBNETS//,/ }; do
  table=$(aws ec2 describe-route-tables --filters "Name=association.subnet-id,Values=$subnet" --query 'RouteTables[0].RouteTableId' --output text)
  [[ "$table" == None ]] && table=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC" "Name=association.main,Values=true" --query 'RouteTables[0].RouteTableId' --output text)
  ROUTE_TABLES+=("$table")
done
ROUTE_TABLES=$(printf '%s\n' "${ROUTE_TABLES[@]}" | sort -u | paste -sd, -)

echo "Builder image: $IMAGE"
echo "Subnets: $SUBNETS  route tables: $ROUTE_TABLES  security group: $SECURITY_GROUP"
aws cloudformation deploy --stack-name "$REPORTS_STACK" --template-file infra/reports.yml \
  --capabilities CAPABILITY_IAM --no-fail-on-empty-changeset --tags PROJECT_NAME=spry \
  --parameter-overrides "BackendImage=$IMAGE" "VpcId=$VPC" "SubnetIds=$SUBNETS" \
  "RouteTableIds=$ROUTE_TABLES" "SecurityGroupId=$SECURITY_GROUP" "DbHost=$DB_HOST" \
  "DbName=$DB_NAME" "DbUser=$DB_USER" "DbSecretArn=$DB_SECRET_ARN" \
  "MailDomain=$REPORT_MAIL_DOMAIN" "Recipients=$REPORT_RECIPIENTS" \
  "ScheduleExpression=${SCHEDULE:-cron(0 7 ? * MON *)}" "FailWeek=${FAIL_WEEK:-}"
aws cloudformation describe-stacks --stack-name "$REPORTS_STACK" \
  --query 'Stacks[0].Outputs[].[OutputKey,OutputValue]' --output table
