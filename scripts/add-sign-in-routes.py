"""Add the Lab 3 sign-in changes to a spry-lab template, leaving everything else as it is.

Usage: add-sign-in-routes.py SOURCE OUTPUT. SOURCE is a JSON template, or the JSON output of
`aws cloudformation get-template --query TemplateBody`. Running it twice changes nothing.
"""

import json
import sys

# The function already deployed to spry-lab: only the two sign-in routes serve the app.
FUNCTION_CODE = (
    "function handler(event) { var r = event.request; "
    "if (['/login', '/login/', '/auth/callback', '/auth/callback/'].indexOf(r.uri) !== -1) "
    "r.uri = '/index.html'; return r; }"
)
ASSOCIATION = {"EventType": "viewer-request", "FunctionARN": {"Fn::GetAtt": ["AuthRoutes", "FunctionARN"]}}
READ_AUTH_OUTPUTS = {
    "Effect": "Allow",
    "Action": "cloudformation:DescribeStacks",
    "Resource": {
        "Fn::Sub": "arn:${AWS::Partition}:cloudformation:us-east-1:${AWS::AccountId}"
        ":stack/spry-auth/*"
    },
}

with open(sys.argv[1]) as source:
    template = json.load(source)
if isinstance(template, str):  # get-template returns the body as a string in some cases
    template = json.loads(template)
resources = template["Resources"]
behavior = resources["Distribution"]["Properties"]["DistributionConfig"]["DefaultCacheBehavior"]


def serves_sign_in_routes(association):
    name = association["FunctionARN"].get("Fn::GetAtt", [None])[0]
    code = resources.get(name, {}).get("Properties", {}).get("FunctionCode", "")
    return "/login/" in code and "/auth/callback/" in code


associations = behavior.get("FunctionAssociations", [])
if not any(serves_sign_in_routes(item) for item in associations):
    if associations:
        sys.exit("The default behavior already has other CloudFront functions; merge them by hand.")
    rebuilt = {}
    for name, resource in resources.items():
        if name == "Distribution":
            rebuilt["AuthRoutes"] = {
                "Type": "AWS::CloudFront::Function",
                "Properties": {
                    "Name": {"Fn::Sub": "${AWS::StackName}-auth-routes"},
                    "AutoPublish": True,
                    "FunctionConfig": {
                        "Comment": "Serve Vite entry point for explicit auth routes only",
                        "Runtime": "cloudfront-js-2.0",
                    },
                    "FunctionCode": FUNCTION_CODE,
                },
            }
        rebuilt[name] = resource
    template["Resources"] = resources = rebuilt
    behavior["FunctionAssociations"] = [ASSOCIATION]

statements = resources["GitHubDeployRole"]["Properties"]["Policies"][0]["PolicyDocument"]["Statement"]
if READ_AUTH_OUTPUTS not in statements:
    statements.append(READ_AUTH_OUTPUTS)

with open(sys.argv[2], "w") as output:
    json.dump(template, output, indent=2)
    output.write("\n")
