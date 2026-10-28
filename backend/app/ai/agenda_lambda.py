"""agenda-parser Lambda behind a function URL: outside the VPC, no database, never writes.

POST {"text": "...", "today": "2026-10-26", "tz": "Europe/Kyiv"} with a Cognito access token.
Saving the agenda goes through the main API, as before.
"""

import base64
import json
import sys
import time
from datetime import date
from zoneinfo import ZoneInfoNotFoundError

from app.ai.agenda import (
    MAX_TEXT_CHARS,
    PARSER_MODEL,
    PROMPT_VERSION,
    AgendaParseError,
    ParserBusy,
    ParserUnavailable,
    cost_usd,
    not_in_text,
    parse_agenda,
)
from app.auth import AuthError, verify_access_token


def log(**fields) -> None:
    print(json.dumps(fields, ensure_ascii=False), file=sys.stdout, flush=True)


def reply(status: int, body: dict) -> dict:
    # CORS headers come from the function URL configuration.
    return {
        "statusCode": status,
        "headers": {"content-type": "application/json"},
        "body": json.dumps(body, ensure_ascii=False),
    }


def read_request(event: dict) -> tuple[str, date, str]:
    raw = event.get("body") or ""
    if event.get("isBase64Encoded"):
        raw = base64.b64decode(raw).decode("utf-8")
    body = json.loads(raw)
    text = body["text"]
    if not isinstance(text, str) or not isinstance(body["tz"], str):
        raise ValueError("text and tz must be strings")
    return text, date.fromisoformat(body["today"]), body["tz"]


def handler(event, context):
    headers = {k.lower(): v for k, v in (event.get("headers") or {}).items()}
    try:
        user = verify_access_token(headers.get("authorization"))
    except AuthError as error:  # every parse costs money: no token, no model call
        return reply(error.status, {"error": error.detail})
    try:
        text, today, tz = read_request(event)
    except (ValueError, KeyError, TypeError):
        return reply(400, {"error": 'Send {"text": ..., "today": "YYYY-MM-DD", "tz": ...}'})
    if len(text) > MAX_TEXT_CHARS:
        return reply(413, {"error": f"The text is longer than {MAX_TEXT_CHARS} characters"})
    if not text.strip():
        return reply(400, {"error": "Paste some text first"})

    started = time.monotonic()
    common = {"user": user["sub"], "model": PARSER_MODEL, "prompt_version": PROMPT_VERSION}
    try:
        agenda, usage = parse_agenda(text, today, tz)
    except ZoneInfoNotFoundError:
        return reply(400, {"error": f"Unknown time zone {tz}"})
    except AgendaParseError as error:
        log(event="agenda_failed", **common, **error.usage, error=str(error),
            latency_ms=int((time.monotonic() - started) * 1000),
            cost_usd=cost_usd(PARSER_MODEL, error.usage))  # fmt: skip
        return reply(422, {"error": "No agenda found in this text"})
    except ParserBusy:
        log(event="agenda_throttled", **common)
        return reply(429, {"error": "The parser is busy, try again in a minute"})
    except ParserUnavailable as error:
        log(event="agenda_unavailable", **common, error=str(error))
        return reply(503, {"error": "The parser is unavailable, type the agenda by hand"})

    log(
        event="agenda_parsed",
        **common,
        **usage,
        latency_ms=int((time.monotonic() - started) * 1000),
        cost_usd=cost_usd(PARSER_MODEL, usage),
        chars=len(text),
        items=len(agenda.items),
    )
    return reply(
        200,
        {
            "agenda": agenda.model_dump(mode="json"),
            "not_in_text": not_in_text(agenda, text),
            "model": PARSER_MODEL,
            "prompt_version": PROMPT_VERSION,
        },
    )
