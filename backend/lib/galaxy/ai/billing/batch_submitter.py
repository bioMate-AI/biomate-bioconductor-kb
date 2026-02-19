"""
AWS Batch Job Submitter with Billing Integration

Drop-in replacement for bare boto3 batch.submit_job() calls.
Adds billing tags automatically and enforces quota before submission.

Usage:
    from galaxy.ai.billing.batch_submitter import submit_batch_job, BatchJobSpec

    spec = BatchJobSpec(
        user_id="user_abc123",
        workflow_id="wf_001",
        job_name="rna-seq-alignment",
        job_queue="biomate-cpu-queue",
        job_definition="biomate-cpu:3",
        vcpus=4,
        memory_mb=16384,
        gpu_count=0,
        instance_type="c6i.xlarge",
        expected_duration_minutes=60,
        command=["python", "run_alignment.py", "--input", "s3://..."],
        environment={"SAMPLE_ID": "S001"},
    )

    job_id = submit_batch_job(spec)
"""

import logging
import os
from dataclasses import dataclass, field
from typing import Optional

import boto3
from botocore.exceptions import ClientError

from .core.quota_enforcer import check_and_reserve, estimate_job_cost, QuotaExceededError

log = logging.getLogger(__name__)

AWS_REGION = os.environ.get("AWS_DEFAULT_REGION", "us-east-1")

_batch_client = None


def _get_batch():
    global _batch_client
    if _batch_client is None:
        _batch_client = boto3.client("batch", region_name=AWS_REGION)
    return _batch_client


@dataclass
class BatchJobSpec:
    # Billing identifiers (REQUIRED)
    user_id: str
    workflow_id: str

    # Batch job config
    job_name: str
    job_queue: str
    job_definition: str

    # Resource requirements
    vcpus: float = 1.0
    memory_mb: int = 2048
    gpu_count: int = 0

    # Billing metadata
    instance_type: str = "FARGATE"      # e.g. "c6i.xlarge", "g4dn.xlarge"
    capacity_type: str = "ON_DEMAND"    # "ON_DEMAND" or "SPOT"
    org_id: str = ""
    expected_duration_minutes: float = 30.0

    # Job content
    command: list[str] = field(default_factory=list)
    environment: dict[str, str] = field(default_factory=dict)
    job_role_arn: Optional[str] = None
    depends_on: list[dict] = field(default_factory=list)
    retry_attempts: int = 1

    # Extra user tags (merged with billing tags)
    extra_tags: dict[str, str] = field(default_factory=dict)


def submit_batch_job(spec: BatchJobSpec) -> str:
    """
    Submit an AWS Batch job with:
      1. Quota check (raises QuotaExceededError if over limit)
      2. Required billing tags on the job
      3. Standard container overrides

    Returns the Batch job ID.
    Raises QuotaExceededError or ClientError on failure.
    """
    # ---- 1. Quota check ------------------------------------------------
    try:
        estimated = estimate_job_cost(
            instance_type=spec.instance_type,
            vcpus=spec.vcpus,
            memory_mb=spec.memory_mb,
            gpu_count=spec.gpu_count,
            expected_duration_minutes=spec.expected_duration_minutes,
            is_spot=(spec.capacity_type == "SPOT"),
        )
    except Exception as exc:
        # Pricing table miss or Redis error — allow submission with a conservative estimate
        log.warning("estimate_job_cost failed (%s); using Fargate fallback for quota check", exc)
        from .core.cost_calculator import FARGATE_VCPU_PRICE_HR, FARGATE_MEM_GB_PRICE_HR
        hours = spec.expected_duration_minutes / 60.0
        estimated = (spec.vcpus * hours * FARGATE_VCPU_PRICE_HR
                     + (spec.memory_mb / 1024.0) * hours * FARGATE_MEM_GB_PRICE_HR)
    check_and_reserve(spec.user_id, estimated_cost_usd=estimated)
    log.info(
        "Quota OK for user=%s estimated=$%.4f job=%s",
        spec.user_id, estimated, spec.job_name,
    )

    # ---- 2. Build billing tags -----------------------------------------
    billing_tags = {
        "user_id":       spec.user_id,
        "workflow_id":   spec.workflow_id,
        "org_id":        spec.org_id or "",
        "instance_type": spec.instance_type,
        "capacity_type": spec.capacity_type,
        "service":       "biomate",
    }
    tags = {**billing_tags, **spec.extra_tags}

    # ---- 3. Container overrides ----------------------------------------
    resource_requirements = [
        {"type": "VCPU",   "value": str(int(spec.vcpus))},
        {"type": "MEMORY", "value": str(spec.memory_mb)},
    ]
    if spec.gpu_count > 0:
        resource_requirements.append({"type": "GPU", "value": str(spec.gpu_count)})

    container_overrides: dict = {
        "resourceRequirements": resource_requirements,
    }
    if spec.command:
        container_overrides["command"] = spec.command
    if spec.environment:
        import re as _re
        _ENV_KEY_RE = _re.compile(r'^[A-Za-z_][A-Za-z0-9_]*$')
        invalid_keys = [k for k in spec.environment if not _ENV_KEY_RE.match(k)]
        if invalid_keys:
            raise ValueError(
                f"Environment variable names must match [A-Za-z_][A-Za-z0-9_]*; "
                f"invalid: {invalid_keys}"
            )
        container_overrides["environment"] = [
            {"name": k, "value": v} for k, v in spec.environment.items()
        ]

    # ---- 4. Submit -------------------------------------------------------
    submit_kwargs: dict = {
        "jobName":           spec.job_name,
        "jobQueue":          spec.job_queue,
        "jobDefinition":     spec.job_definition,
        "containerOverrides": container_overrides,
        "tags":              tags,
        "retryStrategy":     {"attempts": spec.retry_attempts},
    }
    if spec.depends_on:
        submit_kwargs["dependsOn"] = spec.depends_on

    try:
        resp   = _get_batch().submit_job(**submit_kwargs)
        job_id = resp["jobId"]
        log.info("Batch job submitted: %s (user=%s queue=%s)",
                 job_id, spec.user_id, spec.job_queue)
        return job_id
    except ClientError as exc:
        log.error(
            "Batch submit_job failed: %s — quota reservation of $%.4f for user=%s may be leaked",
            exc, estimated, spec.user_id,
        )
        raise


def make_s3_tagged_upload(s3_client, user_id: str, workflow_id: str):
    """
    Returns a helper that wraps s3_client.upload_file / put_object
    with automatic user_id tagging.

    Usage:
        s3 = make_s3_tagged_upload(boto3.client("s3"), user_id, workflow_id)
        s3.upload_file("local.txt", "my-bucket", "results/output.txt")
        s3.put_object(Bucket="my-bucket", Key="results/report.json", Body=b"...")
    """
    tag_str = f"user_id={user_id}&workflow_id={workflow_id}"

    class TaggedS3:
        def upload_file(self, filename, bucket, key, **kwargs):
            extra = kwargs.pop("ExtraArgs", {})
            extra.setdefault("Tagging", tag_str)
            return s3_client.upload_file(filename, bucket, key, ExtraArgs=extra, **kwargs)

        def put_object(self, **kwargs):
            kwargs.setdefault("Tagging", tag_str)
            return s3_client.put_object(**kwargs)

        def __getattr__(self, name):
            # Passthrough for any other S3 methods
            return getattr(s3_client, name)

    return TaggedS3()
