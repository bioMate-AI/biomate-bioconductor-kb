"""
Centralised S3 / MinIO client factory.

When S3_ENDPOINT_URL is set (on-prem MinIO deployments), every boto3 S3
client created here will point at the local MinIO instance instead of AWS.
SaaS deployments leave S3_ENDPOINT_URL unset — behaviour is identical to
the old scattered boto3.client("s3") calls.

Usage:
    from galaxy.ai.s3_utils import make_s3_client, get_s3_bucket

    s3 = make_s3_client()
    bucket = get_s3_bucket()          # raises if no bucket configured
"""

from __future__ import annotations

import logging
import os
from typing import Any, Dict, Optional

import boto3

log = logging.getLogger(__name__)

# Cached per-process client (not thread-unsafe; boto3 clients are thread-safe)
_DEFAULT_REGION = "us-east-1"


def make_s3_client(**kwargs: Any):
    """
    Return a boto3 S3 client configured for either AWS S3 or a local MinIO
    endpoint, depending on the S3_ENDPOINT_URL environment variable.

    Extra kwargs are forwarded to boto3.client() — e.g. region_name,
    aws_access_key_id, aws_secret_access_key for per-user credentials.
    """
    endpoint_url: Optional[str] = os.environ.get("S3_ENDPOINT_URL") or os.environ.get(
        "AWS_ENDPOINT_URL"
    )

    region = kwargs.pop("region_name", None) or os.environ.get(
        "AWS_DEFAULT_REGION", _DEFAULT_REGION
    )

    client_kwargs: Dict[str, Any] = {"region_name": region, **kwargs}

    if endpoint_url:
        client_kwargs["endpoint_url"] = endpoint_url
        # MinIO requires path-style addressing
        from botocore.config import Config  # type: ignore

        client_kwargs["config"] = Config(s3={"addressing_style": "path"})
        log.debug("[S3] Using MinIO endpoint: %s", endpoint_url)
    else:
        log.debug("[S3] Using AWS S3 (region=%s)", region)

    return boto3.client("s3", **client_kwargs)


def get_s3_bucket() -> str:
    """
    Return the configured S3/MinIO bucket name, or raise ValueError if none
    is configured.
    """
    bucket = (
        os.environ.get("S3_BUCKET_NAME")
        or os.environ.get("AWS_S3_BUCKET")
        or os.environ.get("NEXTFLOW_S3_BUCKET")
    )
    if not bucket:
        raise ValueError(
            "No S3 bucket configured. Set S3_BUCKET_NAME in .env "
            "(or AWS_S3_BUCKET / NEXTFLOW_S3_BUCKET for legacy compat)."
        )
    return bucket


def is_minio() -> bool:
    """Return True when running against a local MinIO instance."""
    return bool(os.environ.get("S3_ENDPOINT_URL") or os.environ.get("AWS_ENDPOINT_URL"))


def ensure_bucket_exists(bucket: str) -> None:
    """
    Create the bucket if it doesn't exist (MinIO on-prem helper).
    Safe to call on AWS S3 — it just raises BucketAlreadyOwnedByYou which we swallow.
    """
    s3 = make_s3_client()
    try:
        s3.head_bucket(Bucket=bucket)
        log.debug("[S3] Bucket %r already exists", bucket)
    except Exception:
        try:
            region = os.environ.get("AWS_DEFAULT_REGION", _DEFAULT_REGION)
            if region == "us-east-1":
                s3.create_bucket(Bucket=bucket)
            else:
                s3.create_bucket(
                    Bucket=bucket,
                    CreateBucketConfiguration={"LocationConstraint": region},
                )
            log.info("[S3] Created bucket %r", bucket)
        except Exception as exc:  # noqa: BLE001
            if "BucketAlreadyOwnedByYou" in str(exc) or "BucketAlreadyExists" in str(exc):
                pass
            else:
                log.warning("[S3] Could not create bucket %r: %s", bucket, exc)
