"""S3 storage backend (also the base for MinIO via ``endpoint_url``).

boto3 is imported lazily inside ``_client`` so this module imports cleanly
on hosts without boto3 (pre-sync checklist step 3). The ``endpoint_url``
parameter is the seam Feature ②-B uses for MinIO/on-prem: a MinIO backend
is ``S3Backend(endpoint_url="https://minio.internal:9000")``.
"""

from __future__ import annotations

import os
from typing import Any, Dict, List, Optional

from .base import StorageBackend, StorageObject


class S3Backend(StorageBackend):
    """AWS S3 (or any S3-compatible store via ``endpoint_url``)."""

    def __init__(
        self,
        *,
        region: Optional[str] = None,
        endpoint_url: Optional[str] = None,
    ) -> None:
        self.region = region or os.environ.get("AWS_DEFAULT_REGION", "us-west-2")
        # None for real AWS; set for MinIO / on-prem S3-compatible stores.
        self.endpoint_url = endpoint_url or os.environ.get("S3_ENDPOINT_URL") or None
        self._cached_client = None

    def _client(self):  # pragma: no cover - needs boto3
        if self._cached_client is None:
            import boto3  # lazy: keep module import-safe without AWS libs

            self._cached_client = boto3.client(
                "s3",
                region_name=self.region,
                endpoint_url=self.endpoint_url,
            )
        return self._cached_client

    @staticmethod
    def _split(uri: str) -> tuple[str, str]:
        # s3://bucket/key/parts -> ("bucket", "key/parts")
        rest = uri.split("://", 1)[-1]
        bucket, _, key = rest.partition("/")
        return bucket, key

    def exists(self, uri: str) -> bool:  # pragma: no cover - needs boto3
        bucket, key = self._split(uri)
        try:
            self._client().head_object(Bucket=bucket, Key=key)
            return True
        except Exception:
            return False

    def list_prefix(self, uri_prefix: str) -> List[StorageObject]:  # pragma: no cover - needs boto3
        bucket, prefix = self._split(uri_prefix)
        out: List[StorageObject] = []
        paginator = self._client().get_paginator("list_objects_v2")
        for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
            for obj in page.get("Contents", []) or []:
                key = obj["Key"]
                out.append(
                    StorageObject(
                        uri=f"s3://{bucket}/{key}",
                        filename=key.rsplit("/", 1)[-1],
                        size_bytes=int(obj.get("Size", 0)),
                    )
                )
        return out

    def download(self, uri: str, local_path: str) -> str:  # pragma: no cover - needs boto3
        bucket, key = self._split(uri)
        self._client().download_file(bucket, key, local_path)
        return local_path

    def upload(self, local_path: str, uri: str) -> StorageObject:  # pragma: no cover - needs boto3
        bucket, key = self._split(uri)
        self._client().upload_file(local_path, bucket, key)
        size = 0
        try:
            size = os.path.getsize(local_path)
        except OSError:
            pass
        return StorageObject(uri=uri, filename=key.rsplit("/", 1)[-1], size_bytes=size)

    def tag(self, uri: str, tags: Dict[str, str]) -> bool:  # pragma: no cover - needs boto3
        bucket, key = self._split(uri)
        try:
            self._client().put_object_tagging(
                Bucket=bucket,
                Key=key,
                Tagging={"TagSet": [{"Key": k, "Value": v} for k, v in tags.items()]},
            )
            return True
        except Exception:
            return False
