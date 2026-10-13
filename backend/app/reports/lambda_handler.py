"""report-builder Lambda: runs in the VPC, reads the database, writes reports/<week>.csv to S3.

It is started by a direct invocation ({"source": "schedule"}) or by an SQS record whose body is
{"week": "2026-W40" | null, "source": "schedule" | "manual"}. It never sends email: the file
appearing in S3 is the event the mailer reacts to.
"""

import json
import os
import sys
from datetime import datetime

import boto3

from app.reports.weekly import REPORT_TZ, build_weekly_report, previous_week, report_key

s3 = boto3.client("s3")


def log(message: str, **fields) -> None:
    # One JSON object per line: CloudWatch Logs Insights can filter on trigger and week.
    print(json.dumps({"message": message, **fields}), file=sys.stdout, flush=True)


def requests_from(event: dict) -> list[tuple[str, dict]]:
    """Every (trigger, request) pair in an event: an SQS batch or a single direct call."""
    if event.get("Records"):
        return [
            (detect_trigger(record), json.loads(record.get("body") or "{}"))
            for record in event["Records"]
        ]
    return [(detect_trigger(event), event)]


def detect_trigger(event: dict) -> str:
    if event.get("eventSource") == "aws:sqs":
        body = json.loads(event.get("body") or "{}")
        # The schedule now reaches the builder through the queue; keep saying who asked.
        return "schedule" if body.get("source") == "schedule" else "sqs"
    return "schedule" if event.get("source") == "schedule" else "direct"


def handler(event, context):
    results = []
    for trigger, request in requests_from(event):
        week = request.get("week") or previous_week(datetime.now(REPORT_TZ))
        log(
            "report-builder triggered",
            trigger=trigger,
            via="sqs" if "Records" in event else "invoke",
            source=request.get("source"),
            week=week,
        )
        # Lab exercise: makes one chosen week fail so its message ends up in the DLQ.
        if week == os.getenv("REPORT_FAIL_WEEK"):
            raise RuntimeError(f"Refusing to build {week}: REPORT_FAIL_WEEK is set to it")
        body = build_weekly_report(week)
        key = report_key(week)
        s3.put_object(
            Bucket=os.environ["REPORTS_BUCKET"],
            Key=key,
            Body=body,
            ContentType="text/csv; charset=utf-8",
        )
        log("report saved", trigger=trigger, week=week, key=key, bytes=len(body))
        results.append({"week": week, "key": key})
    return results
