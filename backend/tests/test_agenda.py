import json
from datetime import date
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import text

from app.ai import agenda as parser
from app.ai import agenda_lambda
from app.ai.schemas import ParsedAgenda
from app.auth import AuthError
from app.database import engine
from app.main import app

TODAY = date(2026, 10, 26)
GOOD = {
    "title": "Синк по прайсингу",
    "starts_at": "2026-10-26T10:00:00+02:00",
    "duration_minutes": 45,
    "items": [{"topic": "Нові тарифи Pro", "owner": "Олена", "minutes": 15}],
    "action_items": [{"task": "Порівняння з конкурентами", "owner": "Taras", "due": "2026-10-30"}],
    "language": "uk",
}


def tool_reply(payload, stop_reason="tool_use"):
    blocks = []
    if payload is not None:
        blocks.append(SimpleNamespace(type="tool_use", id="call_1", input=payload))
    usage = SimpleNamespace(input_tokens=1000, output_tokens=200)
    return SimpleNamespace(content=blocks, stop_reason=stop_reason, usage=usage)


class FakeClient:
    def __init__(self, *replies):
        self.replies = list(replies)
        self.calls = []
        self.messages = self

    def create(self, **request):
        self.calls.append(request)
        return self.replies.pop(0)


@pytest.fixture
def model(monkeypatch):
    def install(*replies):
        fake = FakeClient(*replies)
        monkeypatch.setattr(parser, "client", lambda: fake)
        return fake

    return install


def test_valid_agenda_on_first_call(model):
    fake = model(tool_reply(GOOD))
    agenda, usage = parser.parse_agenda("text", TODAY, "Europe/Kyiv")
    assert agenda.items[0].owner == "Олена"
    assert usage == {"input_tokens": 1000, "output_tokens": 200}
    request = fake.calls[0]
    # The date, the zone and the delimited text reach the model; the model ID is configuration.
    assert "Monday 2026-10-26, time zone Europe/Kyiv" in request["messages"][0]["content"]
    assert "Fri 2026-10-30" in request["messages"][0]["content"]  # the calendar
    assert "<pasted_text>\ntext\n</pasted_text>" in request["messages"][0]["content"]
    assert request["model"] == parser.PARSER_MODEL


def test_invalid_output_is_shown_to_the_model_once(model):
    bad = GOOD | {"starts_at": "2026-10-26T10:00:00", "duration_minutes": 9999}
    fake = model(tool_reply(bad), tool_reply(GOOD))
    agenda, usage = parser.parse_agenda("text", TODAY, "Europe/Kyiv")
    assert agenda.duration_minutes == 45 and usage["input_tokens"] == 2000
    feedback = fake.calls[1]["messages"][-1]["content"][0]
    assert feedback["type"] == "tool_result" and feedback["is_error"]


def test_invalid_twice_refusal_and_empty_agenda_are_errors(model):
    bad = GOOD | {"items": [{"topic": ""}]}
    model(tool_reply(bad), tool_reply(bad))
    with pytest.raises(parser.AgendaParseError, match="invalid agenda twice") as error:
        parser.parse_agenda("text", TODAY, "Europe/Kyiv")
    assert error.value.usage["output_tokens"] == 400
    model(tool_reply(None, stop_reason="refusal"))
    with pytest.raises(parser.AgendaParseError, match="refusal"):
        parser.parse_agenda("text", TODAY, "Europe/Kyiv")
    model(tool_reply(GOOD | {"items": [], "action_items": []}))
    with pytest.raises(parser.AgendaParseError, match="no agenda"):
        parser.parse_agenda("milk, bread, eggs", TODAY, "Europe/Kyiv")


def test_offset_comes_from_the_zone_and_blanks_are_none(model):
    # Kyiv switched to winter time on 2026-10-25: +02:00, whatever the model believes.
    reply = GOOD | {"starts_at": "2026-10-29T14:00:00+03:00"}
    reply["items"] = [{"topic": "Budget", "owner": " ", "minutes": 20}]
    model(tool_reply(reply))
    agenda, _ = parser.parse_agenda("text", TODAY, "Europe/Kyiv")
    assert agenda.starts_at == "2026-10-29T14:00:00+02:00"
    assert agenda.items[0].owner is None


def test_language_must_be_a_code(model):
    model(tool_reply(GOOD | {"language": "English"}), tool_reply(GOOD))
    agenda, usage = parser.parse_agenda("text", TODAY, "Europe/Kyiv")
    assert agenda.language == "uk" and usage["input_tokens"] == 2000


def test_cost_and_names_not_in_text():
    usage = {"input_tokens": 1_000_000, "output_tokens": 100_000}
    assert parser.cost_usd("anthropic.claude-opus-5-5", usage) == 6.0
    assert parser.cost_usd("anthropic.claude-haiku-5-5", usage) == 0.15
    agenda = ParsedAgenda.model_validate(GOOD)
    assert parser.not_in_text(agenda, "1) тарифи — Олена") == ["action_items.0.owner"]


class FakeRuntime:
    def __init__(self, *replies):
        self.replies = list(replies)
        self.calls = []

    def converse(self, **request):
        self.calls.append(request)
        reply = self.replies.pop(0)
        if isinstance(reply, Exception):
            raise reply
        return reply


def converse_reply(payload):
    content = [{"toolUse": {"toolUseId": "t1", "name": "record_agenda", "input": payload}}]
    return {
        "output": {"message": {"role": "assistant", "content": content}},
        "stopReason": "tool_use",
        "usage": {"inputTokens": 900, "outputTokens": 150},
    }


def test_converse_backend_for_non_anthropic_models(monkeypatch):
    from botocore.exceptions import ClientError

    monkeypatch.setattr(parser, "PARSER_MODEL", "us.amazon.nova-pro-v1:0")
    bad = GOOD | {"duration_minutes": 0}
    fake = FakeRuntime(converse_reply(bad), converse_reply(GOOD))
    monkeypatch.setattr(parser, "runtime", lambda: fake)
    agenda, usage = parser.parse_agenda("text", TODAY, "Europe/Kyiv")
    assert agenda.items[0].owner == "Олена" and usage["input_tokens"] == 1800
    first = fake.calls[0]
    assert first["toolConfig"]["toolChoice"] == {"tool": {"name": "record_agenda"}}
    assert "$ref" not in json.dumps(first["toolConfig"]["tools"][0]["toolSpec"]["inputSchema"])
    retry = fake.calls[1]["messages"][-1]["content"][0]["toolResult"]
    assert retry["status"] == "error" and retry["toolUseId"] == "t1"

    throttled = ClientError({"Error": {"Code": "ThrottlingException"}}, "Converse")
    monkeypatch.setattr(parser, "runtime", lambda: FakeRuntime(throttled))
    with pytest.raises(parser.ParserBusy):
        parser.parse_agenda("text", TODAY, "Europe/Kyiv")
    denied = ClientError({"Error": {"Code": "AccessDeniedException"}}, "Converse")
    monkeypatch.setattr(parser, "runtime", lambda: FakeRuntime(denied))
    with pytest.raises(parser.ParserUnavailable, match="AccessDenied"):
        parser.parse_agenda("text", TODAY, "Europe/Kyiv")


def call(body, token="Bearer good"):
    event = {"headers": {"Authorization": token}, "body": json.dumps(body)}
    response = agenda_lambda.handler(event, None)
    return response["statusCode"], json.loads(response["body"])


@pytest.fixture
def signed_in(monkeypatch):
    def verify(header):
        if header != "Bearer good":
            raise AuthError(401, "Sign in required")
        return {"sub": "user-1"}

    monkeypatch.setattr(agenda_lambda, "verify_access_token", verify)


def test_handler_parses_and_logs(signed_in, model, capsys):
    model(tool_reply(GOOD))
    status, body = call({"text": "Пн 10:00 Олена", "today": "2026-10-26", "tz": "Europe/Kyiv"})
    assert status == 200 and body["prompt_version"] == parser.PROMPT_VERSION
    assert body["not_in_text"] == ["action_items.0.owner"]
    line = json.loads(capsys.readouterr().out)
    assert line["event"] == "agenda_parsed" and line["user"] == "user-1"
    assert line["cost_usd"] == parser.cost_usd(parser.PARSER_MODEL, line)
    assert {"input_tokens", "output_tokens", "latency_ms", "model"} <= line.keys()


def test_handler_rejects_before_calling_the_model(signed_in, model):
    fake = model()
    request = {"text": "x", "today": "2026-10-26", "tz": "Europe/Kyiv"}
    assert call(request, token="")[0] == 401
    assert call(request | {"text": "x" * 10_001})[0] == 413
    assert call({"text": "x"})[0] == 400
    assert call(request | {"tz": "Mars/Base"})[0] == 400
    assert fake.calls == []


def test_handler_maps_busy_and_unavailable(signed_in, monkeypatch):
    request = {"text": "x", "today": "2026-10-26", "tz": "Europe/Kyiv"}
    for error, status in [(parser.ParserBusy(), 429), (parser.ParserUnavailable("x"), 503)]:

        def fail(*args, error=error):
            raise error

        monkeypatch.setattr(agenda_lambda, "parse_agenda", fail)
        assert call(request)[0] == status


def test_handler_reports_no_agenda(signed_in, model):
    model(tool_reply(GOOD | {"items": [], "action_items": []}))
    request = {"text": "milk", "today": "2026-10-26", "tz": "Europe/Kyiv"}
    assert call(request) == (422, {"error": "No agenda found in this text"})


@pytest.fixture
def meeting():
    assert engine.url.database.endswith("_test"), "Refusing to clear a non-test database"
    with engine.begin() as connection:
        connection.execute(text("DELETE FROM meetings"))
    api = TestClient(app)
    created = api.post(
        "/api/meetings",
        json={
            "title": "Pricing sync",
            "starts_at": "2026-10-26T10:00:00+02:00",
            "ends_at": "2026-10-26T10:45:00+02:00",
            "attendee_count": 3,
        },
    ).json()
    return api, created["id"]


def test_save_agenda_keeps_the_suggestion(meeting):
    api, meeting_id = meeting
    saved_items = [{"topic": "Нові тарифи Pro", "owner": "Олена", "minutes": 20}]
    suggestion = {"agenda": GOOD, "model": "anthropic.claude-opus-5-5", "prompt_version": "v1"}
    response = api.post(
        f"/api/meetings/{meeting_id}/agenda",
        json={"items": saved_items, "ai_suggestion": suggestion},
    )
    assert response.status_code == 200
    assert response.json()["agenda"] == {"items": saved_items, "action_items": []}
    with engine.connect() as connection:
        stored = connection.execute(text("SELECT ai_suggestion FROM meetings")).scalar_one()
    assert stored["agenda"]["items"][0]["minutes"] == 15  # what the model said, before the edit
    assert api.get("/api/meetings").json()[0]["agenda"]["items"][0]["minutes"] == 20


def test_save_agenda_validates(meeting):
    api, meeting_id = meeting
    url = f"/api/meetings/{meeting_id}/agenda"
    assert api.post(url, json={"items": []}).status_code == 422
    assert api.post(url, json={"items": [{"topic": "x", "minutes": 0}]}).status_code == 422
    missing = "/api/meetings/00000000-0000-0000-0000-000000000000/agenda"
    assert api.post(missing, json={"items": [{"topic": "x"}]}).status_code == 404
