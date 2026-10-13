import csv
import io
import json
from datetime import datetime, timezone

import pytest
from sqlalchemy import text

from app.database import SessionLocal, engine
from app.models import Meeting
from app.reports import lambda_handler
from app.reports.weekly import build_weekly_report, previous_week, report_key, week_start


@pytest.fixture(autouse=True)
def clean_database():
    assert engine.url.database.endswith("_test"), "Refusing to clear a non-test database"
    with engine.begin() as connection:
        connection.execute(text("DELETE FROM meetings"))


def add(title, starts_at, ends_at, attendees=3):
    with SessionLocal() as session:
        session.add(
            Meeting(
                title=title,
                starts_at=datetime.fromisoformat(starts_at),
                ends_at=datetime.fromisoformat(ends_at),
                attendee_count=attendees,
            )
        )
        session.commit()


def rows(week):
    return list(csv.reader(io.StringIO(build_weekly_report(week).decode("utf-8-sig"))))


def test_week_helpers():
    assert week_start("2026-W40").isoformat() == "2026-09-28"
    assert report_key("2026-W40") == "reports/2026-W40.csv"
    # Monday 07:00 in Kyiv reports on the week that has just ended, across a year boundary too.
    assert previous_week(datetime(2026, 10, 5, 4, tzinfo=timezone.utc)) == "2026-W40"
    assert previous_week(datetime(2027, 1, 4, 5, tzinfo=timezone.utc)) == "2026-W53"
    for bad in ["2026-40", "last week", "2026-W54", "../2026-W40"]:
        with pytest.raises(ValueError):
            report_key(bad)


def test_totals_change_and_longest_meetings():
    add("Planning", "2026-09-28T10:00:00+03:00", "2026-09-28T12:00:00+03:00", 6)
    add("Standup", "2026-09-29T09:00:00+03:00", "2026-09-29T09:15:00+03:00", 8)
    add("Review", "2026-10-04T23:30:00+03:00", "2026-10-05T00:30:00+03:00", 2)
    # Sunday 23:30 in Kyiv is still W40; Monday 00:00 in Kyiv is already W41.
    add("Next week", "2026-10-05T00:00:00+03:00", "2026-10-05T05:00:00+03:00")
    add("Last week", "2026-09-22T10:00:00+03:00", "2026-09-22T11:00:00+03:00")
    report = rows("2026-W40")
    assert ["week", "2026-W40"] in report
    assert ["meetings", "3", "1", "+2", "+200.0%"] in report
    assert ["hours", "3.25", "1.00", "+2.25", "+225.0%"] in report
    header = ["rank", "title", "starts_at", "duration_hours", "participants"]
    top = report[report.index(header) + 1 :]
    assert [row[1] for row in top] == ["Planning", "Review", "Standup"]
    assert top[0] == ["1", "Planning", "2026-09-28T10:00:00+03:00", "2.00", "6"]


def test_empty_week_and_same_bytes_twice():
    assert ["meetings", "0", "0", "0", ""] in rows("2026-W40")
    assert build_weekly_report("2026-W40") == build_weekly_report("2026-W40")


class FakeS3:
    def __init__(self):
        self.objects = {}

    def put_object(self, Bucket, Key, Body, ContentType):
        self.objects[Key] = Body


def test_handler_accepts_schedule_invoke_and_sqs_records(monkeypatch, capsys):
    s3 = FakeS3()
    monkeypatch.setattr(lambda_handler, "s3", s3)
    monkeypatch.setenv("REPORTS_BUCKET", "bucket")
    lambda_handler.handler({"source": "schedule"}, None)
    sqs = {
        "Records": [
            {"eventSource": "aws:sqs", "body": json.dumps({"week": "2026-W39", "source": "manual"})}
        ]
    }
    result = lambda_handler.handler(sqs, None)
    assert result == [{"week": "2026-W39", "key": "reports/2026-W39.csv"}]
    # Delivered twice: still one file.
    lambda_handler.handler(sqs, None)
    assert "reports/2026-W39.csv" in s3.objects and len(s3.objects) == 2
    triggers = [json.loads(line) for line in capsys.readouterr().out.splitlines()]
    started = [line for line in triggers if line["message"] == "report-builder triggered"]
    assert [line["trigger"] for line in started] == ["schedule", "sqs", "sqs"]


def test_handler_fails_the_chosen_week(monkeypatch):
    monkeypatch.setattr(lambda_handler, "s3", FakeS3())
    monkeypatch.setenv("REPORTS_BUCKET", "bucket")
    monkeypatch.setenv("REPORT_FAIL_WEEK", "2026-W39")
    with pytest.raises(RuntimeError):
        lambda_handler.handler({"week": "2026-W39"}, None)
