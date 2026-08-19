"""The ``StorageBackend`` Protocol and its value types."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Dict, List, Protocol, runtime_checkable


@dataclass
class StorageObject:
    """A single stored object (output file, staged input, ...)."""

    uri: str                       # s3://... or file://... or minio endpoint uri
    filename: str
    size_bytes: int = 0
    extra: Dict[str, Any] = field(default_factory=dict)


@runtime_checkable
class StorageBackend(Protocol):
    """Contract for object storage (S3 today, MinIO / local later)."""

    def exists(self, uri: str) -> bool:
        ...

    def list_prefix(self, uri_prefix: str) -> List[StorageObject]:
        ...

    def download(self, uri: str, local_path: str) -> str:
        ...

    def upload(self, local_path: str, uri: str) -> StorageObject:
        ...

    def tag(self, uri: str, tags: Dict[str, str]) -> bool:
        """Attach key/value tags (used for per-user/run billing attribution)."""
        ...
