import csv, io, json, os, urllib.parse
from email.message import EmailMessage

import boto3

s3 = boto3.client("s3")
ses = boto3.client("sesv2")


def log(message, **fields):
    print(json.dumps({"message": message, **fields}), flush=True)


def handler(event, context):
    recipients = [r.strip() for r in os.environ["RECIPIENTS"].split(",") if r.strip()]
    for record in event["Records"]:
        bucket = record["s3"]["bucket"]["name"]
        key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])
        log("report-mailer triggered", trigger="s3", event=record["eventName"],
            bucket=bucket, key=key, sequencer=record["s3"]["object"].get("sequencer"))
        body = s3.get_object(Bucket=bucket, Key=key)["Body"].read()
        week = key.rsplit("/", 1)[-1].removesuffix(".csv")
        summary = [
            f"{row[0]}: {row[1]} (week before: {row[2]}, change: {row[3]})"
            for row in csv.reader(io.StringIO(body.decode("utf-8-sig")))
            if len(row) >= 4 and row[0] in ("meetings", "hours")
        ]
        msg = EmailMessage()
        msg["Subject"] = f"Spry weekly meetings report {week}"
        msg["From"] = os.environ["SENDER"]
        msg["To"] = ", ".join(recipients)
        msg.set_content(
            f"Meetings in {week}:\n\n" + "\n".join(summary)
            + "\n\nThe five longest meetings are in the attached CSV.\n"
        )
        msg.add_attachment(body, maintype="text", subtype="csv",
                           filename=f"spry-{week}.csv")
        sent = ses.send_email(Content={"Raw": {"Data": msg.as_bytes()}})
        log("report emailed", key=key, recipients=len(recipients),
            message_id=sent["MessageId"])
