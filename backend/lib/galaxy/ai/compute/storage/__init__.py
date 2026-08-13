"""Object-storage backends — the pluggable I/O layer.

Phase 0 defines the :class:`StorageBackend` Protocol and an
:class:`S3Backend` that reserves an ``endpoint_url`` parameter. That single
parameter is what makes Feature ②-B's ``MinIOStorageBackend`` a thin config
subclass rather than a rewrite: MinIO is S3-compatible, so an S3 client
pointed at a MinIO ``endpoint_url`` covers most of the surface.
"""

from __future__ import annotations

from .base import StorageBackend, StorageObject
from .s3 import S3Backend

__all__ = ["StorageBackend", "StorageObject", "S3Backend"]
