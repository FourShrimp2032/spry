"""Convert describe-task-definition output to a register-task-definition request."""
import json
import os
import sys

# Set only when the API must verify Cognito tokens (make deploy-backend PROTECT_API=1).
AUTH_ENV = ("COGNITO_REGION", "COGNITO_USER_POOL_ID", "COGNITO_CLIENT_ID")

with open(sys.argv[1]) as source:
    task = json.load(source)
allowed = {"family", "taskRoleArn", "executionRoleArn", "networkMode", "containerDefinitions",
           "volumes", "placementConstraints", "requiresCompatibilities", "cpu", "memory",
           "pidMode", "ipcMode", "proxyConfiguration", "inferenceAccelerators",
           "ephemeralStorage", "runtimePlatform"}
result = {key: value for key, value in task.items() if key in allowed}
containers = [item for item in result["containerDefinitions"] if item["name"] == "backend"]
if len(containers) != 1:
    sys.exit("Expected exactly one backend container")
containers[0]["image"] = sys.argv[2]
auth = {name: os.environ.get(name, "") for name in AUTH_ENV}
if any(auth.values()) and not all(value and value != "None" for value in auth.values()):
    sys.exit("Incomplete Cognito settings for the API: " + ", ".join(AUTH_ENV))
environment = [item for item in containers[0].get("environment", []) if item["name"] not in auth]
environment += [{"name": name, "value": value} for name, value in auth.items() if value]
containers[0]["environment"] = environment
json.dump(result, sys.stdout, indent=2)
