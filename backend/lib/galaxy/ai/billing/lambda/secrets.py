"""
Secrets Manager helper for Lambda functions.
Fetches secrets once per Lambda execution environment (lru_cache),
then returns the cached value on all subsequent warm invocations — zero overhead.
Falls back gracefully if Secrets Manager is unreachable.
"""
import functools
import logging
import os

log = logging.getLogger(__name__)

_SM_REGION = os.environ.get("AWS_REGION", "us-west-2")


@functools.lru_cache(maxsize=None)
def get_secret(name: str) -> str:
    """
    Fetch a secret from AWS Secrets Manager by name.
    Cached for the lifetime of the Lambda execution environment.
    Returns "" and logs a warning on failure (preserves existing no-op behaviour).
    """
    # Allow env var override so local dev / unit tests don't need SM access
    env_override = os.environ.get(name.split("/")[-1].upper().replace("-", "_"))
    if env_override:
        return env_override
    try:
        import boto3
        sm = boto3.client("secretsmanager", region_name=_SM_REGION)
        return sm.get_secret_value(SecretId=name)["SecretString"]
    except Exception as e:
        log.warning("Could not fetch secret '%s' from Secrets Manager: %s", name, e)
        return ""
