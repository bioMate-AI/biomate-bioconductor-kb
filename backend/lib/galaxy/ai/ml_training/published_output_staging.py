"""Bounded S3 artifact staging for the admin-only central registration bridge."""
from __future__ import annotations
import json
import os
from pathlib import Path, PurePosixPath
from urllib.parse import urlsplit
from .run_registration import StagedTrainingOutputs
from ..drug_discovery.custom_model_registry import artifact_sha256

MAX_ARTIFACT_FILES = 256
MAX_ARTIFACT_BYTES = 512 * 1024 * 1024
MAX_METRICS_BYTES = 2 * 1024 * 1024


def configured_buckets() -> set:
    buckets = {os.environ[key] for key in ('AWS_S3_BUCKET', 'NEXTFLOW_S3_BUCKET', 'S3_BUCKET_NAME',
        'AWS_S3_NEXTFLOW_BUCKET', 'AWS_NF_S3_BUCKET', 'AWS_S3_UPLOAD_BUCKET') if os.environ.get(key)}
    # Same deployment defaults as nextflow_executor fetch_public_data/_upload_bucket.
    # These are storage authority only; Node still binds every URI to an owned run.
    if not buckets:
        buckets.add('biomate-data' if os.environ.get('S3_ENDPOINT_URL') else 'biomate-nextflow-work')
    return buckets


def configured_s3_client():
    import boto3
    from botocore.config import Config
    endpoint = os.environ.get('S3_ENDPOINT_URL')
    kwargs = {'region_name': os.environ.get('AWS_REGION') or os.environ.get('AWS_DEFAULT_REGION') or 'us-west-2'}
    if endpoint:
        kwargs.update(endpoint_url=endpoint, config=Config(signature_version='s3v4', s3={'addressing_style': 'path'}))
        key = os.environ.get('AWS_NF_ACCESS_KEY_ID') or os.environ.get('AWS_ACCESS_KEY_ID') or os.environ.get('MINIO_ROOT_USER')
        secret = os.environ.get('AWS_NF_SECRET_ACCESS_KEY') or os.environ.get('AWS_SECRET_ACCESS_KEY') or os.environ.get('MINIO_ROOT_PASSWORD')
        if key and secret:
            kwargs.update(aws_access_key_id=key, aws_secret_access_key=secret)
    elif os.environ.get('AWS_NF_ACCESS_KEY_ID') and os.environ.get('AWS_NF_SECRET_ACCESS_KEY'):
        kwargs.update(aws_access_key_id=os.environ['AWS_NF_ACCESS_KEY_ID'],
                      aws_secret_access_key=os.environ['AWS_NF_SECRET_ACCESS_KEY'])
    return boto3.client('s3', **kwargs)


def _source(uri: str, allowed_buckets: set) -> tuple:
    value = urlsplit(uri)
    if value.scheme != 's3' or value.netloc not in allowed_buckets or not value.path.lstrip('/') or value.query or value.fragment or '\x00' in uri:
        raise ValueError('Only configured-bucket S3 output references are accepted')
    return value.netloc, value.path.lstrip('/')


def _relative(value: str) -> str:
    if not value or '\\' in value or '\x00' in value or value.startswith('/'):
        raise ValueError('Invalid artifact relative path')
    parts = value.split('/')
    if any(part in ('', '.', '..') for part in parts):
        raise ValueError('Invalid artifact relative path')
    return str(PurePosixPath(value))


def _read(client, source: tuple, limit: int, target=None):
    response = client.get_object(Bucket=source[0], Key=source[1])
    body = response['Body']
    count, data = 0, bytearray()
    try:
        if response.get('ContentLength', 0) > limit:
            raise ValueError('Training output exceeds size limit')
        while True:
            chunk = body.read(min(65536, limit + 1 - count))
            if not chunk:
                break
            count += len(chunk)
            if count > limit:
                raise ValueError('Training output exceeds size limit')
            if target is not None:
                target.write(chunk)
            else:
                data.extend(chunk)
    finally:
        body.close()
    return count if target is not None else bytes(data)


def stage_published_outputs(client, allowed_buckets: set, artifacts: list, metrics_s3_uri: str,
                            staging_root: str) -> StagedTrainingOutputs:
    if not allowed_buckets:
        raise ValueError('Model artifact storage bucket is not configured')
    if not artifacts or len(artifacts) > MAX_ARTIFACT_FILES:
        raise ValueError('Invalid number of training artifact files')
    sources, paths, prepared = set(), set(), []
    for item in artifacts:
        source = _source(item['s3_uri'], allowed_buckets)
        relative = _relative(item['relative_path'])
        if source in sources or relative in paths:
            raise ValueError('Duplicate training artifact reference')
        sources.add(source); paths.add(relative); prepared.append((source, relative))
    metrics_source = _source(metrics_s3_uri, allowed_buckets)
    if metrics_source in sources:
        raise ValueError('Metrics must be separate from model artifacts')
    root = Path(staging_root) / 'artifact'
    root.mkdir(parents=True, exist_ok=False)
    total = 0
    for source, relative in prepared:
        target = root / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open('xb') as handle:
            total += _read(client, source, MAX_ARTIFACT_BYTES - total, handle)
    document = json.loads(_read(client, metrics_source, MAX_METRICS_BYTES))
    if not isinstance(document, dict):
        raise ValueError('Training metrics must be a JSON object')
    return StagedTrainingOutputs(str(root), artifact_sha256(str(root)), document)
