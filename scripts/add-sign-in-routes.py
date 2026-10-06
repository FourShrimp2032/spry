"""Add the Lab 3 sign-in changes to a spry-lab template, leaving everything else as it is.

Usage: add-sign-in-routes.py SOURCE OUTPUT. SOURCE is a JSON template, or the JSON output of
`aws cloudformation get-template --query TemplateBody`. Running it twice changes nothing.
"""

import json
import sys

FUNCTION_CODE = """function handler(event) {
  var request = event.request;
  // Client-side routes such as /login/ and /auth/callback/ have no S3 object: serve the app.
  var last = request.uri.split('/').pop();
  if (last.indexOf('.') === -1) request.uri = '/index.html';
  return request;
}
"""
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

if "SpaRouteFunction" not in resources:
    rebuilt = {}
    for name, resource in resources.items():
        if name == "Distribution":
            rebuilt["SpaRouteFunction"] = {
                "Type": "AWS::CloudFront::Function",
                "Properties": {
                    "Name": {"Fn::Sub": "${AWS::StackName}-spa-routes"},
                    "AutoPublish": True,
                    "FunctionConfig": {
                        "Comment": "Serve index.html for client-side routes",
                        "Runtime": "cloudfront-js-2.0",
                    },
                    "FunctionCode": FUNCTION_CODE,
                },
            }
        rebuilt[name] = resource
    template["Resources"] = resources = rebuilt

behavior = resources["Distribution"]["Properties"]["DistributionConfig"]["DefaultCacheBehavior"]
if "FunctionAssociations" in behavior and behavior["FunctionAssociations"] != [
    {"EventType": "viewer-request", "FunctionARN": {"Fn::GetAtt": ["SpaRouteFunction", "FunctionARN"]}}
]:
    sys.exit("The default behavior already has other CloudFront functions; merge them by hand.")
behavior["FunctionAssociations"] = [
    {"EventType": "viewer-request", "FunctionARN": {"Fn::GetAtt": ["SpaRouteFunction", "FunctionARN"]}}
]

statements = resources["GitHubDeployRole"]["Properties"]["Policies"][0]["PolicyDocument"]["Statement"]
if READ_AUTH_OUTPUTS not in statements:
    statements.append(READ_AUTH_OUTPUTS)

with open(sys.argv[2], "w") as output:
    json.dump(template, output, indent=2)
    output.write("\n")
