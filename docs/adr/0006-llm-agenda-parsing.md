# ADR 0006 — Parse pasted agendas with Claude on Bedrock, outside the VPC

- Status: accepted
- Date: 2026-10-26
- Lab 6, Part 4

## Context

Agendas arrive as emails, chat messages and notes, not as forms. "Paste an agenda" turns that text into a structured agenda the user checks and saves. Constraints:

- **No NAT.** The API's private side and the database have no route to the internet (Labs 2–5), and Bedrock is on the internet. A NAT gateway (~$33/month) or an interface endpoint (~$7.30/month per AZ) would end "$0 when idle".
- **Cost per click.** Every parse costs tokens, so the endpoint must be authenticated and limited.
- **Text from outside.** Pasted emails can contain instructions ("ignore your instructions…"). The model's output is a suggestion, never an action.
- **Wrong answers look right.** A model can return a plausible date or name that is not in the text, with HTTP 200.

## Decision

- **Model:** Claude Opus 5.5 (`anthropic.claude-opus-5-5`) through the Anthropic Messages API on Bedrock (`bedrock-mantle`, us-east-1), effort `low`. The model ID is configuration (`PARSER_MODEL`).
- **Amendment, 2026-10-28:** this account's Claude quota is 0 tokens/min (new account, AWS Support case open), so the deployed parser runs **Amazon Nova Pro** (`us.amazon.nova-pro-v1:0`) through the provider-neutral **Converse API**. `parse_agenda()` has two backends behind one interface (`MessagesApi`, `ConverseApi`), chosen by the model ID; the tool, prompt, schema, validation and logging are shared. Switching back to Claude is `make deploy-ai PARSER_MODEL=anthropic.claude-opus-5-5`. Lesson: the thin layer between our code and one vendor's SDK paid for itself within a day.
- **Contract is a schema.** The model answers by calling `record_agenda`, whose input schema is `ParsedAgenda` (pydantic). Output is validated; the validation error is shown to the model once; then a clear 422. Unknown values stay `null`; owners that do not occur in the text are flagged `not in text` in the UI.
- **The parser runs outside the VPC** as its own Lambda (`spry-agenda-parser`, backend image, function URL). It needs no database: text in, JSON out. It reaches Bedrock and Cognito's JWKS over the internet with no NAT and no endpoint, and costs $0 while unused.
- **The model never writes.** The browser shows a pre-filled form; the user edits and presses Save, which goes to the existing API (`POST /api/meetings/{id}/agenda`) with its validation. The API stores the final agenda and, next to it, the AI suggestion with model and prompt version (`ai_suggestion` JSONB).
- **Protection:** Cognito access token required (401 otherwise), text ≤ 10,000 characters (413), today's date and time zone sent by the browser, pasted text delimited and declared as data in the system prompt. IAM role instead of an API key. A $5 monthly AWS Budgets alarm.

## Alternatives considered

| Alternative | Why it lost |
|---|---|
| Call Bedrock from the API, in the VPC, through a `bedrock-mantle` interface endpoint | ~$7.30/month per AZ (≈$14.60 for two) for a feature used a few times a week, and it puts an LLM call (2–8 s) on the API's request path. Worth it only for a chat that must read the database. |
| Claude API (api.anthropic.com) directly | Needs an API key to store and rotate, a second bill outside AWS Budgets, and no IAM, CloudTrail or cost tags. Same model and request shape, so switching later is cheap. |
| A regular-expression parser | Free and deterministic, but agendas come in any language and layout ("15 хв", "15 min", "Olena — pricing", "pricing (Olena)"). Each new format is new code, and relative dates ("next Tuesday after lunch") need a date parser per language anyway. |

## Consequences

- **Cost:** measured on Nova Pro ≈ $0.0017 per parse (1,300 input, 20–730 output tokens); estimated on Opus 5.5 ≈ $0.014. Details in `docs/LAB6-ANSWERS.md`. Idle cost $0; the budget alarm caps surprises.
- **Logged:** one JSON line per parse in `/aws/lambda/spry-agenda-parser`: user (Cognito `sub`), model, prompt version, input/output tokens, latency, cost, text length, item count. Not the pasted text itself (it may contain personal data).
- **Quality signal:** the diff between `ai_suggestion` and the saved agenda, per prompt version.
- **When Bedrock is down or throttling:** the parser answers 503/429 with a clear message; the user types the agenda by hand in the same form. Meetings, sign-in, agendas and the weekly report keep working, because nothing else depends on the parser.
- **Risks:** a public URL invites abuse by signed-up accounts (no per-user quota yet); the role may call any Bedrock model (`Resource: "*"`).
