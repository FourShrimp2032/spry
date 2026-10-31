# Lab 7 — From CloudFormation to Terraform

The infrastructure of Labs 4–6 (sign-in, weekly report, agenda parser, budget) was four CloudFormation stacks deployed from a laptop. It is now one Terraform configuration in `infra/`, with its state in HCP Terraform, planned on every pull request and applied on every merge to `main`. Nothing in AWS was re-created: the user pool keeps its users, the bucket keeps its reports. Decision: [ADR 0007](adr/0007-terraform.md).

```
pull request ──► HCP Terraform (spry-dev): plan as a check
merge to main ─► HCP Terraform: plan + apply ──OIDC token──► IAM role hcp-terraform-ooad-fourshrimp2032 ──► AWS
push to main ──► GitHub Actions: tests, image, ECS, site (unchanged since Lab 2)
```

## Layout

| File | Was | What |
|---|---|---|
| `infra/versions.tf` | | `cloud` block (organization `ooad-fourshrimp2032`, workspace `spry-dev`), providers `aws` 6.x (eu-north-1 + alias `us_east_1`) and `archive`, `default_tags` with `PROJECT_NAME` |
| `infra/variables.tf`, `infra/terraform.tfvars` | stack parameters, `.env`, values read by the scripts | Non-secret values in Git; `google_client_secret` is a sensitive variable in the workspace |
| `infra/auth.tf` | `infra/auth.yml` | User pool, Google provider, web client, domain, managed login branding |
| `infra/reports.tf` | `infra/reports.yml` | Bucket (+ 6 settings resources), S3 gateway endpoint, queue + DLQ, schedule, two Lambdas, roles, SES identities. The mailer code moved from `ZipFile` to `infra/mailer/index.py` |
| `infra/ai.tf` | `infra/ai.yml`, `infra/budget.yml` | Parser Lambda, function URL, both permissions, role, log group, $5 budget, now in one file and one plan although they sit in two regions |
| `infra/outputs.tf` | stack outputs | Everything the Makefile reads: `terraform output -raw queue_url` |
| `infra/bootstrap/main.tf` | | IAM OIDC provider for app.terraform.io and the role the workspace assumes; trust limited to `workspace:spry-dev` |

The course stack `spry-lab` stays CloudFormation; `data "aws_cloudformation_stack" "main"` reads the site URL, CloudFront domain and backend security group from it.

Lab 5's circular dependency is gone: the bucket, `aws_lambda_permission.mailer_s3` and `aws_s3_bucket_notification.reports` are three resources, and references order them. The bucket name is still `spry-reports-<account>` only because renaming a bucket replaces it.

## The migration (Step 3)

1. **Retain.** `DeletionPolicy: Retain` and `UpdateReplacePolicy: Retain` on all 29 resources of the four templates, deployed with the previous parameters (commit `3730b7c`). Checked: the deployed templates retain 5/5, 17/17, 6/6 and 1/1.
2. **Stacks deleted:** `spry-auth`, `spry-reports`, `spry-ai`, `spry-ai-budget`. Checked afterwards: user pool `spry-users` with its 2 users, 6 reports in the bucket, three functions, the budget; the parser URL still answers 401 without a token.
3. **Import.** `imports.tf` had 42 `import` blocks with the IDs from the stacks. The plan converged in two rounds:

| First plan | Cause | Fix in HCL |
|---|---|---|
| `aws_cognito_user_pool_client.web` **must be replaced** (new client ID = every sign-in broken) | `generate_secret = false` written out; an imported client has no value for it, and it forces replacement | Removed; false is the default |
| `aws_cognito_managed_login_branding.web` **must be replaced** | Followed from the client's new ID | Fixed with the client |
| `aws_lambda_permission.mailer_s3` **must be replaced** | `function_name` given as ARN, AWS stores the name | `function_name = aws_lambda_function.mailer.function_name` |
| `aws_lambda_function.parser` env changes | Followed from the client | Fixed with the client |
| Google provider: `attribute_mapping.username` removed | Cognito adds `username = sub` for Google | Written out, with the six provider details Cognito fills in |
| Both queues: `max_message_size` 1048576 → 262144 | AWS's default is now 1 MiB, the provider's 256 KiB | `max_message_size = 1048576` |
| Schedule `input`: whitespace | `jsonencode` writes JSON without spaces | The literal string from the template |

Final import plan, run remotely in HCP Terraform with the workspace's OIDC credentials:

```
Plan: 42 to import, 0 to add, 3 to change, 0 to destroy.
```

The three in-place changes are harmless:

- `aws_cognito_identity_provider.google`: the client secret becomes marked as sensitive; Terraform says "The value is unchanged".
- `aws_lambda_function.builder`: the image moves from the Lab 5 build `91fb6e7` to `6fdc767`, the image the parser already runs (it contains the report code). `DB_PASSWORD` shows as changed only in sensitivity; checked equal to the secret.
- `aws_lambda_function.mailer`: the same `index.py` is uploaded from a file instead of the template's `ZipFile`.

Nothing was re-created; there was no resource that had to be.

## Commands

```bash
terraform login        # once
make infra-plan        # speculative plan in HCP Terraform (cannot apply)
make infra-output
make frontend-env      # Cognito IDs and the parser URL -> frontend/.env.production, commit it
make reports-ls        # these now read terraform output
make report-now WEEK=2026-W43
```

There is no `apply` in the Makefile. `scripts/deploy-auth.sh`, `deploy-reports.sh` and `deploy-ai.sh` are deleted with the templates. CI checks `terraform fmt` and `terraform validate`; HCP Terraform plans and applies.

The Lab 5 exercises are now variables: `schedule_expression = "rate(5 minutes)"` or `fail_week = "2026-W01"` in `terraform.tfvars`, through a pull request.

## What to submit

1. Commit link: https://github.com/FourShrimp2032/spry/commit/8428ad1 (the migration; `3730b7c` retained the stacks first)
2. Screenshot: an HCP Terraform run of `spry-dev` triggered by a push or merge, ending in **Apply finished**.
3. `terraform plan` after the migration ending in **No changes. Your infrastructure matches the configuration.**
