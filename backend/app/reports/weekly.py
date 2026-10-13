"""Weekly meetings report: one ISO week in, one CSV out. No AWS here."""

import csv
import io
import os
import re
import sys
from datetime import date, datetime, time, timedelta
from zoneinfo import ZoneInfo

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.database import SessionLocal
from app.models import Meeting

# Week boundaries are Monday 00:00 in this zone, the same local week the team lives in.
REPORT_TZ = ZoneInfo(os.getenv("REPORT_TIMEZONE", "Europe/Kyiv"))
WEEK_PATTERN = re.compile(r"^(\d{4})-W(\d{2})$")
TOP_MEETINGS = 5


def week_start(week: str) -> date:
    """Monday of an ISO week such as "2026-W40". Raises ValueError for anything else."""
    match = WEEK_PATTERN.match(week)
    if not match:
        raise ValueError(f"Expected an ISO week like 2026-W40, got {week!r}")
    return date.fromisocalendar(int(match[1]), int(match[2]), 1)


def iso_week(day: date) -> str:
    year, week, _ = day.isocalendar()
    return f"{year}-W{week:02d}"


def previous_week(now: datetime) -> str:
    """The ISO week before the one `now` falls in, in the report's time zone."""
    return iso_week(now.astimezone(REPORT_TZ).date() - timedelta(days=7))


def report_key(week: str) -> str:
    # One week, one name: a rebuilt report overwrites the old file instead of adding a second.
    week_start(week)
    return f"reports/{week}.csv"


def _bounds(monday: date) -> tuple[datetime, datetime]:
    start = datetime.combine(monday, time(), REPORT_TZ)
    return start, datetime.combine(monday + timedelta(days=7), time(), REPORT_TZ)


def _totals(session: Session, monday: date) -> tuple[int, float]:
    start, end = _bounds(monday)
    seconds = func.extract("epoch", Meeting.ends_at - Meeting.starts_at)
    count, total = session.execute(
        select(func.count(), func.coalesce(func.sum(seconds), 0)).where(
            Meeting.starts_at >= start, Meeting.starts_at < end
        )
    ).one()
    return count, float(total) / 3600


def _longest(session: Session, monday: date) -> list[Meeting]:
    start, end = _bounds(monday)
    return session.scalars(
        select(Meeting)
        .where(Meeting.starts_at >= start, Meeting.starts_at < end)
        .order_by((Meeting.ends_at - Meeting.starts_at).desc(), Meeting.starts_at, Meeting.id)
        .limit(TOP_MEETINGS)
    ).all()


def _hours(value: float) -> str:
    return f"{value:.2f}"


def _change(current: float, previous: float, fmt) -> tuple[str, str]:
    delta = current - previous
    percent = f"{delta / previous * 100:+.1f}%" if previous else ""
    return ("+" if delta > 0 else "") + fmt(delta), percent


def build_weekly_report(week: str, session: Session | None = None) -> bytes:
    """Query the meetings of one ISO week (e.g. "2026-W40") and return the CSV."""
    monday = week_start(week)
    before = monday - timedelta(days=7)
    if session is None:
        with SessionLocal() as own_session:
            return build_weekly_report(week, own_session)

    count, hours = _totals(session, monday)
    previous_count, previous_hours = _totals(session, before)
    start, end = _bounds(monday)

    # No "generated at" line: the same data always gives the same bytes.
    out = io.StringIO()
    rows = csv.writer(out, lineterminator="\n")
    rows.writerow(["Spry weekly meetings report"])
    rows.writerow(["week", week])
    rows.writerow(["from", start.isoformat()])
    rows.writerow(["to", end.isoformat()])
    rows.writerow(["previous_week", iso_week(before)])
    rows.writerow([])
    rows.writerow(["metric", "this_week", "previous_week", "change", "change_percent"])
    rows.writerow(["meetings", count, previous_count, *_change(count, previous_count, str)])
    rows.writerow(
        [
            "hours",
            _hours(hours),
            _hours(previous_hours),
            *_change(hours, previous_hours, _hours),
        ]
    )
    rows.writerow([])
    rows.writerow(["longest_meetings"])
    rows.writerow(["rank", "title", "starts_at", "duration_hours", "participants"])
    for rank, meeting in enumerate(_longest(session, monday), start=1):
        duration = (meeting.ends_at - meeting.starts_at).total_seconds() / 3600
        rows.writerow(
            [
                rank,
                meeting.title,
                meeting.starts_at.astimezone(REPORT_TZ).isoformat(),
                _hours(duration),
                meeting.attendee_count,
            ]
        )
    # utf-8-sig: Excel opens Cyrillic titles correctly only with the BOM.
    return out.getvalue().encode("utf-8-sig")


if __name__ == "__main__":
    # Local check against the compose database: python -m app.reports.weekly 2026-W40
    target = sys.argv[1] if len(sys.argv) > 1 else previous_week(datetime.now(REPORT_TZ))
    sys.stdout.buffer.write(build_weekly_report(target))
