"""
AWS Lambda: S3 Event Handler

Triggered by S3 Event Notifications (via SQS → Lambda).
Configure on the BioMate results bucket for:
  - s3:ObjectCreated:*   (PUT, COPY, POST, CompleteMultipartUpload)
  - s3:ObjectRemoved:*   (DELETE)

SQS event records contain S3 notification payloads.

Set environment variables:
  BILLING_API_URL  - internal BioMate billing service
  BILLING_API_KEY  - shared secret
  USER_TAG_NAME    - the S3 object tag key that stores user_id (default: "user_id")

S3 objects MUST be tagged at upload time with:
  user_id = <biomate_user_id>
  workflow_id = <workflow_run_id>

Tag them in application code when calling s3.put_object or via S3 PutObjectTagging.
"""

import json
import os
import logging
import urllib.parse

import boto3

try:
    import httpx
except ImportError:
    httpx = None  # type: ignore

log = logging.getLogger()
log.setLevel(logging.INFO)

BILLING_API_URL = os.environ.get("BILLING_API_URL", "")
BILLING_API_KEY = os.environ.get("BILLING_API_KEY", "")
USER_TAG_NAME   = os.environ.get("USER_TAG_NAME", "user_id")

s3_client = boto3.client("s3")


def _get_object_tags(bucket: str, key: str) -> dict:
    """Fetch S3 object tags as a plain dict."""
    try:
        resp = s3_client.get_object_tagging(Bucket=bucket, Key=key)
        return {t["Key"]: t["Value"] for t in resp.get("TagSet", [])}
    except Exception as exc:
        log.warning("get_object_tagging failed s3://%s/%s: %s", bucket, key, exc)
        return {}


def _get_object_size(bucket: str, key: str) -> int:
    """Returns object size in bytes, or 0 on error."""
    try:
        head = s3_client.head_object(Bucket=bucket, Key=key)
        return int(head.get("ContentLength", 0))
    except Exception:
        return 0


def _notify_billing(event_type: str, payload: dict) -> None:
    if not BILLING_API_URL or httpx is None:
        return
    try:
        with httpx.Client(timeout=10.0) as client:
            client.post(
                f"{BILLING_API_URL}/internal/billing/{event_type}",
                json=payload,
                headers={"X-Internal-Key": BILLING_API_KEY},
            )
    except Exception as exc:
        log.error("billing notify failed: %s", exc)


def _process_record(s3_record: dict) -> None:
    event_name = s3_record.get("eventName", "")
    bucket     = s3_record["s3"]["bucket"]["name"]
    key        = urllib.parse.unquote_plus(s3_record["s3"]["object"]["key"])
    size_bytes = int(s3_record["s3"]["object"].get("size", 0))

    tags = _get_object_tags(bucket, key)
    user_id     = tags.get(USER_TAG_NAME, "unknown")
    workflow_id = tags.get("workflow_id", "unknown")

    if user_id == "unknown":
        log.warning("No user_id tag on s3://%s/%s — skipping billing", bucket, key)
        return

    if event_name.startswith("ObjectCreated"):
        if size_bytes == 0:
            size_bytes = _get_object_size(bucket, key)
        # Reject implausible sizes: negative or above S3's 5 TiB max object size
        _MAX_S3_OBJECT_BYTES = 5 * 1024 ** 4  # 5 TiB
        if not (0 <= size_bytes <= _MAX_S3_OBJECT_BYTES):
            log.error(
                "Implausible object size %d for s3://%s/%s — skipping billing",
                size_bytes, bucket, key,
            )
            return
        log.info("S3 PUT user=%s bucket=%s size=%d", user_id, bucket, size_bytes)
        _notify_billing("s3_put", {
            "user_id":     user_id,
            "workflow_id": workflow_id,
            "bucket":      bucket,
            "key":         key,
            "size_bytes":  size_bytes,
        })

    elif event_name.startswith("ObjectRemoved"):
        # Deletion reduces future storage cost — update storage ledger
        log.info("S3 DELETE user=%s bucket=%s key=%s", user_id, bucket, key)
        _notify_billing("s3_delete", {
            "user_id":    user_id,
            "workflow_id": workflow_id,
            "bucket":     bucket,
            "key":        key,
        })


def handler(event: dict, context) -> dict:
    """
    SQS-wrapped S3 event records.
    event.Records[].body = JSON string containing an S3 notification.
    """
    for sqs_record in event.get("Records", []):
        try:
            body = json.loads(sqs_record.get("body", "{}"))
            for s3_record in body.get("Records", []):
                _process_record(s3_record)
        except Exception as exc:
            log.error("Failed to process SQS record: %s", exc)
            # Do NOT raise — allows SQS to continue processing remaining messages

    return {"statusCode": 200}
