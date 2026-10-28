# Lab 6 — Paste an agenda (Claude on Amazon Bedrock)

The user pastes an email, a chat message or notes into a meeting. Claude turns it into a structured agenda, the app shows the pre-filled form, the user checks it and presses **Save**. The model suggests; the person decides.

```
browser ──① POST text + Cognito token──► agenda-parser (Lambda, function URL, outside the VPC)
                                            │ ② Messages API (bedrock-mantle, us-east-1), IAM role
                                            ▼
                                         Claude Opus 5.5 ──► record_agenda(...) ──► validated JSON
browser ◄────────────── pre-filled form, "suggested" badges ──────┘
browser ──③ Save: POST /api/meetings/{id}/agenda──► API (ECS, VPC) ──► PostgreSQL
                                                       agenda + ai_suggestion (model, prompt version)
```

Diagram (C4, level 2): [architecture.md](architecture.md). Decision: [adr/0006-llm-agenda-parsing.md](adr/0006-llm-agenda-parsing.md). Answers and the test table: [LAB6-ANSWERS.md](LAB6-ANSWERS.md).

## What was added

| Part | File | What it does |
|---|---|---|
| Contract | `backend/app/ai/schemas.py` | `AgendaItem`, `ActionItem`, `ParsedAgenda` (pydantic). `starts_at` must carry a UTC offset |
| Parser | `backend/app/ai/agenda.py` | `parse_agenda(text, today, tz)` with two backends, `MessagesApi` (Claude, bedrock-mantle) and `ConverseApi` (Nova and other Bedrock models), chosen by `PARSER_MODEL`: one `record_agenda` tool, today's date, zone and a two-week calendar in the prompt, the user's real UTC offset applied in code, pasted text inside `<pasted_text>` and declared as data; validation error shown to the model once, then `AgendaParseError`; an empty agenda is an error too. `not_in_text()` flags owners that do not occur in the text. `PROMPT_VERSION = "agenda-v2"`, model from `PARSER_MODEL` |
| Lambda | `backend/app/ai/agenda_lambda.py` | Cognito access token (401), text ≤ 10,000 chars (413), 422 no agenda, 429 throttled, 503 Bedrock unavailable. One JSON log line per parse |
| Token check | `backend/app/auth.py` | `verify_access_token()` shared by the API and the parser |
| Save | `backend/app/main.py`, migration `0002_agenda.py` | `POST /api/meetings/{id}/agenda` validates and stores `agenda` and `ai_suggestion` (JSONB): what the model suggested, model, prompt version |
| Screen | `frontend/src/AgendaDialog.jsx` | **Add agenda / Edit agenda** on every meeting → Paste an agenda → **Parse** (progress with seconds, **Cancel** via AbortController) → pre-filled form; fields filled by the AI carry a *suggested* badge until touched, names not found in the text a *not in text* badge; Save through the API; every error has its own message, and the form always works by hand |
| Infrastructure | `infra/ai.yml`, `infra/budget.yml`, `scripts/deploy-ai.sh` | Lambda from the backend image (`app.ai.agenda_lambda.handler`, no VPC, 30 s, 512 MB), role with `bedrock-mantle:CreateInference`, function URL (AuthType NONE, CORS: the site's origins, POST only), both public-URL permissions; $5 monthly budget alarm (us-east-1, the only region CloudFormation supports budgets in) |
| Commands | `Makefile` | `llm-hello`, `parse TEXT=…`, `deploy-ai`, `parser-logs` |
| Tests | `backend/tests/test_agenda.py` | Fake model client: retry after a validation error, refusal, empty agenda, cost; handler 401/413/400 before any model call; save keeps the suggestion |
| Test inputs | `backend/app/ai/cases.py` | The five Step 5 inputs: `python -m app.ai.cases` |

## Run it

```bash
# laptop, with your AWS login (aws login needs: pip install "botocore[crt]")
pip install -r backend/requirements.txt "botocore[crt]"
make llm-hello
make parse TEXT="Пн 10:00, синк по прайсингу, 45 хв. 1) нові тарифи Pro — Олена, 15 хв"
make parse TEXT="..." PARSER_MODEL=us.amazon.nova-lite-v1:0

# deploy (after CI has deployed an image that contains the parser)
make deploy-ai          # writes frontend/.env.production with the parser URL; commit it
make parser-logs
```

Bedrock needs, per account: the Anthropic use-case form, a Marketplace agreement per model, a **Paid** AWS plan (Free-plan accounts cannot use Marketplace models) and a non-zero quota. This account had all but the last: its Claude quota is 0 tokens/min until AWS Support lifts it, so the deployed parser runs **Amazon Nova Pro** through the Converse API (`PARSER_MODEL=us.amazon.nova-pro-v1:0`, the Makefile default for now). When AWS lifts it: `make deploy-ai PARSER_MODEL=anthropic.claude-opus-5-5`.

## The screen recording (≤ 45 s)

1. Open https://app.antonyivaso.dynv6.net/ and sign in.
2. Start recording: **⌘⇧5** → *Record Selected Portion* → select the browser window → *Record*.
3. On a meeting press **Add agenda**, paste the Ukrainian example, press **Parse**.
4. When the form appears with *suggested* badges, change one field (for example minutes 15 → 20).
5. Press **Save agenda**: the agenda appears under the meeting.
6. Stop recording (the ■ icon in the menu bar). The video lands on the Desktop as `.mov`. QuickTime → *File → Export As → 720p* if it is too large; for MP4: `ffmpeg -i in.mov -vcodec h264 out.mp4`.

## What to submit

1. Commit link: https://github.com/FourShrimp2032/spry/commit/4fb0a05 (parser, `infra/ai.yml`, screen, ADR); Nova backend and prompt v2 in `6fdc767`.
2. The screen recording.
3. The test table and 4. the CloudWatch log line and 5. the answers: [LAB6-ANSWERS.md](LAB6-ANSWERS.md).

## Teardown

`aws cloudformation delete-stack --region eu-north-1 --stack-name spry-ai` and `aws cloudformation delete-stack --region us-east-1 --stack-name spry-ai-budget`. Remove `frontend/.env.production` to hide the paste box.
