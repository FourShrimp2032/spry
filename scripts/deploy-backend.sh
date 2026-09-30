#!/usr/bin/env bash
set -euo pipefail
: "${AWS_REGION:?}" "${ECR_REPOSITORY:?}" "${ECS_CLUSTER:?}" "${ECS_SERVICE:?}" "${TASK_FAMILY:?}" "${ECS_SUBNETS:?}" "${ECS_SECURITY_GROUP:?}"
SHA="${GITHUB_SHA:-$(git rev-parse HEAD)}"
[[ "$SHA" =~ ^[0-9a-f]{40}$ ]] || { echo 'A full commit SHA is required'; exit 1; }
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGISTRY="$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
IMAGE="$REGISTRY/$ECR_REPOSITORY:$SHA"
# Re-running a SHA deploy reuses its immutable image.
if aws ecr describe-images --repository-name "$ECR_REPOSITORY" --image-ids "imageTag=$SHA" > /dev/null 2>&1; then
  echo "Reusing immutable image $SHA"
else
  aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$REGISTRY"
  docker buildx build --platform linux/amd64 --push -t "$IMAGE" backend
fi
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
aws ecs describe-task-definition --task-definition "$TASK_FAMILY" --query taskDefinition > "$TMP_DIR/current.json"
python3 scripts/render-task.py "$TMP_DIR/current.json" "$IMAGE" > "$TMP_DIR/next.json"
TASK_ARN=$(aws ecs register-task-definition --cli-input-json "file://$TMP_DIR/next.json" --query 'taskDefinition.taskDefinitionArn' --output text)
NETWORK="awsvpcConfiguration={subnets=[$ECS_SUBNETS],securityGroups=[$ECS_SECURITY_GROUP],assignPublicIp=${ECS_ASSIGN_PUBLIC_IP:-DISABLED}}"
# One migration task; web tasks never run migrations at startup in production.
aws ecs run-task --cluster "$ECS_CLUSTER" --task-definition "$TASK_ARN" --launch-type FARGATE --network-configuration "$NETWORK" --overrides '{"containerOverrides":[{"name":"backend","command":["alembic","upgrade","head"]}]}' > "$TMP_DIR/migration.json"
MIGRATION_ARN=$(python3 - "$TMP_DIR/migration.json" <<'PYCODE'
import json, sys
result = json.load(open(sys.argv[1]))
if result.get('failures') or not result.get('tasks'):
    sys.exit('Migration task could not start: ' + str(result.get('failures')))
print(result['tasks'][0]['taskArn'])
PYCODE
)
aws ecs wait tasks-stopped --cluster "$ECS_CLUSTER" --tasks "$MIGRATION_ARN"
EXIT_CODE=$(aws ecs describe-tasks --cluster "$ECS_CLUSTER" --tasks "$MIGRATION_ARN" --query 'tasks[0].containers[?name==`backend`].exitCode | [0]' --output text)
[[ "$EXIT_CODE" == 0 ]] || { echo "Migration failed: $MIGRATION_ARN ($EXIT_CODE)"; exit 1; }
aws ecs update-service --cluster "$ECS_CLUSTER" --service "$ECS_SERVICE" --task-definition "$TASK_ARN" --desired-count 1 > /dev/null
aws ecs wait services-stable --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE"
ACTUAL_TASK=$(aws ecs describe-services --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE" --query 'services[0].taskDefinition' --output text)
[[ "$ACTUAL_TASK" == "$TASK_ARN" ]] || { echo 'Deployment rolled back'; exit 1; }
echo "Deployed $IMAGE"
