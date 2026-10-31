# ADR 0007 — Terraform for the infrastructure added since Lab 4, applied by HCP Terraform

- Status: accepted
- Date: 2026-10-31
- Lab 7, Part 2

## Context

Labs 4–6 added three CloudFormation stacks next to the course stack `spry-lab`: `spry-auth` (Cognito, us-east-1), `spry-reports` (the weekly report) and `spry-ai` (the agenda parser), plus `spry-ai-budget` (us-east-1, because CloudFormation offers budgets only there). They were deployed from a laptop by `scripts/deploy-*.sh`, which read their inputs from other stacks, the running ECS task and `.env`. Problems:

- **Who changes it.** Only the person with the scripts, AWS credentials and the `.env` could deploy. Nothing reviewed a change before it reached AWS, and the inputs were assembled at deploy time, not written down.
- **More than AWS.** Spry already depends on things outside one AWS account: the Google OAuth client, GitHub, the DNS records at dynv6 (Lab 5). One region per stack also split one feature into two stacks.
- **A second environment** (stage, or a white-label copy) would mean copying four stacks and four scripts.
- **Data.** The user pool holds real accounts (Lab 4) and the bucket holds every report (Lab 5): the migration must not re-create them.

## Decision

- **Terraform**, one root module in `infra/` (`auth.tf`, `reports.tf`, `ai.tf`, `variables.tf`, `outputs.tf`, `versions.tf`), AWS provider 6.x with an `aws.us_east_1` alias, so Cognito and the budget sit in the same plan as the rest. `default_tags` puts `PROJECT_NAME` on everything. The course stack `spry-lab` (network, database, API, site) stays CloudFormation; Terraform reads its outputs with `data "aws_cloudformation_stack"`.
- **State and runs in HCP Terraform**, organization `ooad-fourshrimp2032`, workspace `spry-dev`, Remote execution, connected to the GitHub repository with working directory `infra`. A pull request gets a speculative plan as a check; a merge to `main` plans and applies. The Makefile has `infra-plan` and `infra-output`, and no apply.
- **No AWS keys anywhere.** The workspace uses dynamic credentials: each run gets an OIDC token from app.terraform.io and assumes `hcp-terraform-ooad-fourshrimp2032`, whose trust allows only `workspace:spry-dev` of this organization. The OIDC provider and the role are `infra/bootstrap`, applied once from a laptop (workspace `spry-bootstrap`, Local execution, state in HCP Terraform).
- **Adopted, not re-created.** All 29 CloudFormation resources were set to `DeletionPolicy: Retain`, the stacks deleted, and the resources imported with `import` blocks: 42 Terraform resources (an S3 bucket with inline settings is 7 resources; inline IAM policies and attachments are separate). The first plan was `42 to import, 0 to add, 3 to change, 0 to destroy`; none of the three changes touches data (see [LAB7.md](../LAB7.md)). `prevent_destroy` guards the user pool and the reports bucket.
- **Two roads.** GitHub Actions still builds and deploys the application (image, ECS, site). HCP Terraform deploys the infrastructure. The site's public settings (Cognito IDs, parser URL) are a committed `frontend/.env.production` written by `make frontend-env`, so CI does not need access to Terraform. The image the two image Lambdas run is `backend_image` in `terraform.tfvars`: updating them is a pull request.

## Alternatives

- **Stay on CloudFormation.** AWS keeps the state and rolls back failed changes, and it was working. But it stops at the AWS account (Google, GitHub, DNS stay manual), splits one feature across regions, and our "pipeline" for it was a laptop.
- **AWS CDK.** Real code and good AWS coverage, but it still produces CloudFormation (same limits) and adds a language toolchain to the infrastructure.
- **OpenTofu.** The same files and commands, MPL licence instead of BSL. The course and HCP Terraform use Terraform; the files would move to OpenTofu unchanged if the licence ever mattered.
- **CI runs Terraform (GitHub Actions + OIDC + S3 state).** Equally valid and keeps one pipeline; HCP Terraform gives locking, state history, plan checks on pull requests and dynamic credentials with no state bucket to build first.

## Consequences

- **Who can change the infrastructure:** anyone who can get a pull request merged into `main`. The plan in the check is what gets reviewed. Direct `terraform apply` from a laptop is for emergencies; the workspace can be locked to forbid it.
- **Secrets.** The Google client secret is a sensitive Terraform variable in the workspace (not in Git, hidden in plans). The database password is read from Secrets Manager at plan time and written into the builder's environment, as CloudFormation did. Both are in plain text **in the state**, which HCP Terraform encrypts and keeps with every version; anyone with read access to the workspace's state can read them. Team access to `spry-dev` must stay narrow.
- **If HCP Terraform is down,** the running system is not affected: it only changes infrastructure. Infrastructure changes wait. In an emergency the owner can download the latest state version, switch the workspace to Local execution and plan/apply from a laptop with their own credentials, then switch back.
- **No automatic rollback.** A failed apply stops halfway; the fix is a new commit and another apply.
- **Drift is visible.** Every plan compares with the real resources; a console change shows up and is put back by the next apply unless the code is changed too. A hot fix in the console must be followed by the same change in a pull request.
- **Names stay CloudFormation's.** The adopted IAM roles and Lambda permission statements keep their generated names (`spry-reports-BuilderRole-oVnLteSaUYGU`), because renaming forces replacement.
- **The bootstrap role is AdministratorAccess.** Narrowing it to the services in `infra/` (Cognito, Lambda, S3, SQS, Scheduler, SES, IAM roles under a path, Logs, Budgets) is the next step.
