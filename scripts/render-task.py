"""Convert describe-task-definition output to a register-task-definition request."""
import json
import sys

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
json.dump(result, sys.stdout, indent=2)
