# Spry — containers (C4, level 2)

Updated in Lab 6 with the agenda parser, Bedrock, and the two paths: **parse** (browser → parser → Bedrock) and **save** (browser → API → PostgreSQL).

```mermaid
flowchart LR
  user([Team lead<br/>browser])
  subgraph AWS["AWS account"]
    subgraph edge["eu-north-1 — public"]
      cf[CloudFront + S3<br/>React SPA]
      parser["agenda-parser<br/>Lambda, function URL<br/><i>outside the VPC</i>"]
      mailer[report-mailer<br/>Lambda]
    end
    subgraph vpc["eu-north-1 — VPC, no NAT"]
      api[Spry API<br/>FastAPI on ECS Fargate<br/>behind ALB]
      db[(PostgreSQL<br/>RDS<br/>meetings, agenda,<br/>ai_suggestion)]
      builder[report-builder<br/>Lambda]
    end
    cognito[Cognito<br/>user pool, us-east-1]
    bedrock[Amazon Bedrock<br/>Claude Opus 5.5<br/>us-east-1]
    s3r[(S3 reports)]
    ses[SES]
  end

  user -->|HTTPS| cf
  user -->|sign in| cognito
  user ==>|"① parse: POST text + token"| parser
  parser ==>|"② Messages API, IAM role"| bedrock
  parser -.->|JWKS| cognito
  user -->|"③ save: POST /api/meetings/{id}/agenda"| api
  api -->|SQL| db
  builder -->|SQL| db
  builder --> s3r -->|ObjectCreated| mailer --> ses
```

The parser has no arrow to the database: it receives text and returns JSON. Only the API writes.
