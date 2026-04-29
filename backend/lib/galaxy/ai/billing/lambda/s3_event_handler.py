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

user_id resolution (in priority order):
  1. S3 object tag `user_id`  — set by s3-client.ts for direct user uploads
  2. S3 key path prefix:
       users/{user_id}/uploads/...      → user upload path
       nextflow/outputs/{user_id}/...   → Nextflow publishDir (per-user namespace)
       nextflow/work/{user_id}/...      → Nextflow work dir (per-user namespace)
  3. Skip billing — log a warning and return

This two-tier approach covers both tagged user uploads and untagged Nextflow outputs
that are routed through per-user S3 path prefixes (set by nextflow_executor.py).
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

from .secrets import get_secret

BILLING_API_URL = os.environ.get("BILLING_API_URL", "")
BILLING_API_KEY = get_secret("biomate/billing/api-key")  # SM; env var BILLING_API_KEY overrides in dev
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


def _user_id_from_key(key: str) -> str:
    """
    Extract user_id from the S3 object key path.

    Supported patterns:
      users/{user_id}/uploads/...            → direct UI uploads (s3-client.ts)
      nextflow/outputs/{user_id}/{run_id}/... → Nextflow publishDir
      nextflow/work/{user_id}/{run_id}/...   → Nextflow work dir

    Returns empty string if no pattern matches.
    """
    parts = key.split("/")
    # Pattern: users/{user_id}/...
    if len(parts) >= 3 and parts[0] == "users":
        return parts[1]
    # Pattern: nextflow/outputs/{user_id}/... or nextflow/work/{user_id}/...
    if len(parts) >= 3 and parts[0] == "nextflow" and parts[1] in ("outputs", "work"):
        return parts[2]
    return ""


def _process_record(s3_record: dict) -> None:
    event_name = s3_record.get("eventName", "")
    bucket     = s3_record["s3"]["bucket"]["name"]
    key        = urllib.parse.unquote_plus(s3_record["s3"]["object"]["key"])
    size_bytes = int(s3_record["s3"]["object"].get("size", 0))

    tags = _get_object_tags(bucket, key)
    user_id     = tags.get(USER_TAG_NAME, "")
    workflow_id = tags.get("workflow_id", "unknown")

    # Fallback: extract user_id from the S3 key path (Nextflow outputs + user upload paths)
    if not user_id:
        user_id = _user_id_from_key(key)
        if user_id:
            log.info("user_id resolved from key path: %s → %s", key, user_id)

    if not user_id:
        log.warning("No user_id tag or path match for s3://%s/%s — skipping billing", bucket, key)
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
