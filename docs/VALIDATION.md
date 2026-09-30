# Local verification — 2026-09-30

- Docker Compose build and startup: all 3 services healthy.
- Backend: Ruff lint and formatting passed; 14 tests (API integration and database configuration) passed against PostgreSQL `spry_test`.
- Alembic: upgrade → downgrade base → upgrade completed on the disposable test DB.
- Frontend: ESLint, Prettier and production Vite build passed on macOS and inside the Linux frontend container.
- Responsive UI: checked at 390px; no horizontal overflow.
- Browser: created Weekly product sync, Design review and Sprint planning through the form; data remained after page reload.
- Resilience: stopped local Postgres; GET /api/meetings returned HTTP 503 with the documented message; restarted Postgres and all 3 records returned again without an API restart.
- Local browser verification used three demonstration meetings. A fresh clone starts with an empty database.
- CloudFormation template passed cfn-lint with no errors or warnings.
- Deployment shell scripts passed bash syntax checks; Docker Compose config validated.

## AWS verification — 2026-09-30

- CloudFormation `spry-lab` in eu-north-1 created successfully; OIDC trust update completed.
- GitHub [run 36727682803, attempt 2](https://github.com/FourShrimp2032/spry/actions/runs/36727682803/attempts/2): all checks and both deployment targets succeeded.
- Initial attempt exposed the new immutable GitHub OIDC subject format. The exact owner/repository IDs now restrict trust to this repository's main branch; no wildcard was added.
- Separate Alembic ECS migration task exited 0. Fargate web task became healthy behind ALB.
- Public HTTPS `/health` returned 200 with `{"status":"ok"}`; `/api/meetings` returned 200.
- Browser on https://d310vkwtz8a1f0.cloudfront.net created Weekly product sync, Design review and Sprint planning. All three remained after page reload; API returned the same records.
- `docs/meetings-screenshot.jpg` is the actual CloudFront frontend after reload, with 3 meetings and 18 attendee places.
- Frontend and API share the temporary CloudFront hostname. Own-domain DNS, ACM and ALB HTTPS listener remain outstanding; see SUBMISSION.md.
