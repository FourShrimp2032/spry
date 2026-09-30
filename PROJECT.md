# Spry — repository specification

## Decision
One monorepo makes API, schema, migrations, UI and delivery changes atomic. An agent can inspect the entire contract in one tree. For a small team, shared context outweighs independent release boundaries.

## First slice (specified before implementation)
- `backend/app/`: FastAPI HTTP endpoints in `main.py`, SQLAlchemy mapping in `models.py`, validated request/response models in `schemas.py`, persistence operations in `services.py`, engine/session lifecycle in `database.py`; `config.py` builds a safe database URL from local DATABASE_URL or ECS-injected credentials.
- `backend/alembic/`: migration runner configuration and `versions/` containing ordered, reversible schema revisions. Migrations execute at container start locally, never at image build.
- `backend/tests/`: API integration tests against an isolated PostgreSQL database.
- `frontend/src/`: one React meetings page, list and create form; `components/ui/` contains owned shadcn-style Button and Card primitives; `lib/` contains class-name utilities. Tailwind provides styling. No routing, queues, cache or other application services.
- Root `docker-compose.yml`: exactly postgres, backend and frontend. Each application has its own Dockerfile. New developers install Docker Desktop and run `docker compose up`.

## Versions
Python image `python:3.12.10-slim-bookworm`; Postgres image `postgres:16.9-bookworm`; Node image `node:22.16.0-bookworm-slim`. Python direct dependencies are exact-pinned in requirements files; frontend direct dependencies are exact-pinned in package.json and transitive versions locked in package-lock.json. FastAPI 0.115.12, SQLAlchemy 2.0.41, Alembic 1.16.1, psycopg 3.2.9; React 19.1.0, Vite 6.3.5, Tailwind 3.4.17. These are reproducible selected versions, not a claim to use the latest releases.

## API contract
`GET /api/meetings` → 200 JSON array, ordered by starts_at then id. Empty database → `[]`.
Each object: `id` UUID string; `title` trimmed nonempty string, maximum 200 characters; `starts_at` and `ends_at` RFC3339 strings with explicit timezone, stored and returned in UTC; `attendee_count` integer from 0 through 2147483647. End must be strictly after start.
`POST /api/meetings` accepts all fields except id and returns the persisted object with status 201. Unknown fields, missing fields, invalid times, negative/non-integer attendee counts and blank titles → 422 FastAPI validation detail. All fields are required. No authentication in this lab slice.
`GET /health` → 200 `{ "status": "ok" }` only if the database answers SELECT 1. Database connection errors → 503 `{ "detail": "Database temporarily unavailable" }`. Sessions roll back on failure; connection pre-ping replaces stale connections for later requests. No automatic retries of writes.
Browser calls backend directly through `VITE_API_URL` (default http://localhost:8000); CORS permits the configured frontend origin only.

## Compose contract
- postgres: internal 5432, no host-published port; named volume `postgres_data`; no dependency; pg_isready health check every 5 seconds.
- backend: internal/host 8000 (host binding 127.0.0.1); depends on healthy postgres; Alembic upgrade head precedes Uvicorn; /health checked every 5 seconds.
- frontend: internal/host 5173 (host binding 127.0.0.1); depends on healthy backend; Vite binds 0.0.0.0; HTTP health check. Node dependencies are installed inside its image. No host dependency installation required.
Local database credentials are development-only defaults. Database loss after startup is handled by API error handling, not depends_on.

## Delivery extension required by the second half of the lab
- `.github/workflows/`: push/PR lint, API integration tests and frontend build; deployment on main after green checks, using GitHub OIDC.
- `scripts/`: repeatable AWS deploy operations called by root Makefile, including a one-off ECS migration before service update.
- `infra/`: ECS task and narrowly scoped GitHub OIDC trust templates; `aws-stack.json` defines the infrastructure for user-run CloudFormation provisioning; nothing is provisioned by the assistant.
- `docs/`: AWS setup, lab discussion answers, and submission checklist. No AWS credentials or account-specific invented values.
Frontend delivery is static S3 + CloudFront with a private origin; backend delivery is ECR + ECS Fargate + ALB. Production PostgreSQL is persistent RDS with CA/hostname-verified TLS and reachable only from the backend security group. Production migrations run once per deploy, not in each web task. Deployment uses commit-SHA tags, health checks, HTTPS custom domains and configured ACM certificates.

## Upstream adaptation
Source: https://github.com/dobosevych/OneTwoThree. Its existing back/front application includes authentication, participants, nginx and Lambda infrastructure outside this lab slice. The lab branch replaces those working-tree files with the specified backend/frontend structure; upstream history preserves the original. This avoids competing Compose files and duplicate pipelines.

## User-directed AWS setup (no domain yet)
The user performs all AWS actions in Safari/CloudShell. `scripts/aws-preflight.sh` is read-only; `aws-create.sh` explicitly creates billable resources. CloudFormation starts ECS at desired count 0 with a bootstrap image reference; the first successful GitHub deploy installs a commit-SHA image and sets count 1. No NAT gateway. The initial CloudFront URL handles both frontend and uncached API paths; the CloudFront-to-ALB hop is HTTP with a secret origin header until custom-domain TLS is configured. This is an interim demo and does not satisfy the lab custom-domain/ALB-HTTPS requirement. Passwords are generated by Secrets Manager and injected into ECS; no key is sent to GitHub.
