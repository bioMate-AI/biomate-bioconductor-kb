"""
Galaxy Data Manager

Handles data staging, retrieval, and management for Galaxy workflows
running on cloud platforms.
"""

import hashlib
import logging
import os
import tempfile
from pathlib import Path
from typing import Dict, List, Optional, Any, Union
from dataclasses import dataclass
import asyncio
from urllib.parse import urlparse

from galaxy_cloud.factory import CloudStorageFactory
from galaxy_cloud.core.storage import CloudStorage

from .models import (
    DatasetInfo, CollectionInfo, CloudDatasetMapping,
    WorkflowRunConfig
)


logger = logging.getLogger(__name__)


@dataclass
class StagingResult:
    """Result of data staging operation"""
    success: bool
    cloud_uri: str
    checksum: Optional[str] = None
    size_bytes: Optional[int] = None
    error_message: Optional[str] = None


@dataclass
class RetrievalResult:
    """Result of data retrieval operation"""
    success: bool
    local_path: str
    dataset_info: Optional[DatasetInfo] = None
    error_message: Optional[str] = None


class GalaxyDataManager:
    """
    Manages data staging and retrieval for Galaxy workflows in cloud environments.

    This class handles:
    - Staging Galaxy datasets to cloud storage
    - Retrieving outputs from cloud storage
    - Dataset format conversion and validation
    - Metadata preservation and tracking
    - Efficient data transfer with checksums
    """

    def __init__(self, storage_config: Dict[str, Any]):
        self.storage_config = storage_config
        self.logger = logging.getLogger(f"{self.__class__.__module__}.{self.__class__.__name__}")

        # Storage clients for different providers
        self.storage_clients: Dict[str, CloudStorage] = {}

        # Dataset mappings
        self.dataset_mappings: Dict[str, CloudDatasetMapping] = {}

        # Staging cache
        self.staging_cache: Dict[str, str] = {}  # checksum -> cloud_uri

    async def initialize_storage_client(self, provider: str, config: Dict[str, Any]) -> CloudStorage:
        """Initialize storage client for a provider"""
        if provider not in self.storage_clients:
            # Map provider name to storage scheme
            scheme_mapping = {
                'aws': 's3',
                'gcp': 'gs',
                'azure': 'az',
                'kubernetes': 'pv'
            }
            storage_scheme = scheme_mapping.get(provider, provider)

            storage_client = CloudStorageFactory.create(storage_scheme, config)
            await storage_client.__aenter__()
            self.storage_clients[provider] = storage_client

        return self.storage_clients[provider]

    async def stage_dataset(
        self,
        dataset_info: DatasetInfo,
        run_config: WorkflowRunConfig
    ) -> str:
        """Stage a Galaxy dataset to cloud storage"""

        self.logger.info(f"Staging dataset {dataset_info.dataset_id}")

        try:
            # Calculate checksum for deduplication
            checksum = await self._calculate_file_checksum(dataset_info.file_path)

            # Check cache first
            if checksum in self.staging_cache:
                self.logger.info(f"Dataset {dataset_info.dataset_id} found in cache")
                return self.staging_cache[checksum]

            # Get storage client
            storage_client = await self.initialize_storage_client(
                run_config.cloud_provider,
                self.storage_config.get(run_config.cloud_provider, {})
            )

            # Generate cloud URI
            cloud_uri = self._generate_cloud_uri(
                dataset_info,
                run_config.staging_area,
                run_config.cloud_provider
            )

            # Upload file
            await storage_client.upload_file(dataset_info.file_path, cloud_uri)

            # Verify upload
            if await storage_client.exists(cloud_uri):
                # Create mapping
                mapping = CloudDatasetMapping(
                    dataset_id=dataset_info.dataset_id,
                    galaxy_path=dataset_info.file_path,
                    cloud_uri=cloud_uri,
                    cloud_provider=run_config.cloud_provider,
                    staged=True,
                    checksum=checksum
                )
                self.dataset_mappings[dataset_info.dataset_id] = mapping

                # Cache result
                self.staging_cache[checksum] = cloud_uri

                self.logger.info(f"Successfully staged dataset {dataset_info.dataset_id} to {cloud_uri}")
                return cloud_uri

            else:
                raise Exception(f"Failed to verify upload of {dataset_info.dataset_id}")

        except Exception as e:
            self.logger.error(f"Failed to stage dataset {dataset_info.dataset_id}: {e}")
            raise

    async def stage_collection(
        self,
        collection_info: CollectionInfo,
        run_config: WorkflowRunConfig
    ) -> List[str]:
        """Stage a Galaxy dataset collection to cloud storage"""

        self.logger.info(f"Staging collection {collection_info.collection_id}")

        cloud_uris = []

        try:
            # Stage each element in the collection
            for element in collection_info.elements:
                cloud_uri = await self.stage_dataset(element, run_config)
                cloud_uris.append(cloud_uri)

            self.logger.info(f"Successfully staged collection {collection_info.collection_id}")
            return cloud_uris

        except Exception as e:
            self.logger.error(f"Failed to stage collection {collection_info.collection_id}: {e}")
            raise

    async def retrieve_dataset(
        self,
        cloud_uri: str,
        run_config: WorkflowRunConfig,
        target_path: Optional[str] = None
    ) -> DatasetInfo:
        """Retrieve a dataset from cloud storage"""

        self.logger.info(f"Retrieving dataset from {cloud_uri}")

        try:
            # Get storage client
            storage_client = await self.initialize_storage_client(
                run_config.cloud_provider,
                self.storage_config.get(run_config.cloud_provider, {})
            )

            # Determine target path
            if not target_path:
                # Create temporary file
                temp_dir = Path(tempfile.gettempdir()) / "galaxy-cloud-retrieval"
                temp_dir.mkdir(exist_ok=True)

                # Extract filename from cloud URI
                parsed_uri = urlparse(cloud_uri)
                filename = Path(parsed_uri.path).name
                target_path = str(temp_dir / filename)

            # Download file
            await storage_client.download_file(cloud_uri, target_path)

            # Get file info
            file_size = os.path.getsize(target_path)
            file_ext = Path(target_path).suffix.lstrip('.')

            # Create dataset info
            dataset_info = DatasetInfo(
                dataset_id=f"retrieved-{hash(cloud_uri)}",
                history_id="cloud-execution",
                name=Path(target_path).stem,
                file_ext=file_ext,
                file_size=file_size,
                file_path=target_path
            )

            self.logger.info(f"Successfully retrieved dataset to {target_path}")
            return dataset_info

        except Exception as e:
            self.logger.error(f"Failed to retrieve dataset from {cloud_uri}: {e}")
            raise

    async def retrieve_collection(
        self,
        cloud_uris: List[str],
        run_config: WorkflowRunConfig,
        target_dir: Optional[str] = None
    ) -> CollectionInfo:
        """Retrieve a dataset collection from cloud storage"""

        self.logger.info(f"Retrieving collection with {len(cloud_uris)} elements")

        try:
            elements = []

            # Create target directory if not provided
            if not target_dir:
                temp_dir = Path(tempfile.gettempdir()) / "galaxy-cloud-collection"
                temp_dir.mkdir(exist_ok=True)
                target_dir = str(temp_dir)

            # Retrieve each element
            for idx, cloud_uri in enumerate(cloud_uris):
                parsed_uri = urlparse(cloud_uri)
                filename = Path(parsed_uri.path).name
                target_path = os.path.join(target_dir, f"element_{idx}_{filename}")

                dataset_info = await self.retrieve_dataset(cloud_uri, run_config, target_path)
                elements.append(dataset_info)

            # Create collection info
            collection_info = CollectionInfo(
                collection_id=f"retrieved-collection-{hash(tuple(cloud_uris))}",
                history_id="cloud-execution",
                name="Retrieved Collection",
                collection_type="list",
                elements=elements
            )

            self.logger.info(f"Successfully retrieved collection with {len(elements)} elements")
            return collection_info

        except Exception as e:
            self.logger.error(f"Failed to retrieve collection: {e}")
            raise

    async def sync_staging_area(
        self,
        local_dir: str,
        run_config: WorkflowRunConfig,
        exclude_patterns: Optional[List[str]] = None
    ) -> List[str]:
        """Sync entire directory to staging area"""

        self.logger.info(f"Syncing directory {local_dir} to staging area")

        try:
            storage_client = await self.initialize_storage_client(
                run_config.cloud_provider,
                self.storage_config.get(run_config.cloud_provider, {})
            )

            cloud_uris = []
            local_path = Path(local_dir)

            # Walk through directory
            for file_path in local_path.rglob('*'):
                if file_path.is_file():
                    # Check exclude patterns
                    if exclude_patterns and any(
                        file_path.match(pattern) for pattern in exclude_patterns
                    ):
                        continue

                    # Generate cloud URI
                    relative_path = file_path.relative_to(local_path)
                    cloud_uri = f"{run_config.staging_area}/{relative_path}"

                    # Upload file
                    await storage_client.upload_file(str(file_path), cloud_uri)
                    cloud_uris.append(cloud_uri)

            self.logger.info(f"Synced {len(cloud_uris)} files to staging area")
            return cloud_uris

        except Exception as e:
            self.logger.error(f"Failed to sync staging area: {e}")
            raise

    async def cleanup_staging_area(self, run_config: WorkflowRunConfig, prefix: str = ""):
        """Clean up staging area after workflow completion"""

        self.logger.info(f"Cleaning up staging area with prefix: {prefix}")

        try:
            storage_client = await self.initialize_storage_client(
                run_config.cloud_provider,
                self.storage_config.get(run_config.cloud_provider, {})
            )

            # List and delete files
            deleted_count = 0
            async for file_uri in storage_client.list_files(f"{run_config.staging_area}/{prefix}"):
                await storage_client.delete(file_uri)
                deleted_count += 1

            self.logger.info(f"Cleaned up {deleted_count} files from staging area")

        except Exception as e:
            self.logger.error(f"Failed to cleanup staging area: {e}")
            # Don't raise - cleanup failures shouldn't break workflow

    def _generate_cloud_uri(
        self,
        dataset_info: DatasetInfo,
        staging_area: str,
        cloud_provider: str
    ) -> str:
        """Generate cloud URI for a dataset"""

        # Use dataset ID and extension for the filename
        filename = f"{dataset_info.dataset_id}.{dataset_info.file_ext}"

        # Map provider name to URI scheme
        provider_scheme_map = {
            'aws': 's3',
            's3': 's3',
            'gcp': 'gs',
            'gcs': 'gs',
            'azure': 'az',
            'azblob': 'az',
            'kubernetes': 'pv'
        }

        scheme = provider_scheme_map.get(cloud_provider.lower())

        # Construct full URI based on scheme
        if scheme == 's3':
            return f"s3://{staging_area.lstrip('s3://')}/{filename}"
        elif scheme == 'gs':
            return f"gs://{staging_area.lstrip('gs://')}/{filename}"
        elif scheme == 'az':
            return f"az://{staging_area.lstrip('az://')}/{filename}"
        elif scheme == 'pv':
            return f"pv://{staging_area.lstrip('pv://')}/{filename}"
        else:
            # Default: return path without scheme
            return f"{staging_area}/{filename}"

    async def _calculate_file_checksum(self, file_path: str) -> str:
        """Calculate MD5 checksum of a file"""
        hash_md5 = hashlib.md5()

        try:
            with open(file_path, "rb") as f:
                # Read file in chunks to handle large files
                for chunk in iter(lambda: f.read(4096), b""):
                    hash_md5.update(chunk)

            return hash_md5.hexdigest()

        except Exception as e:
            self.logger.warning(f"Failed to calculate checksum for {file_path}: {e}")
            return ""

    async def validate_dataset(self, dataset_info: DatasetInfo) -> bool:
        """Validate a dataset before processing"""
        try:
            # Check if file exists
            if not os.path.exists(dataset_info.file_path):
                self.logger.error(f"Dataset file not found: {dataset_info.file_path}")
                return False

            # Check file size
            actual_size = os.path.getsize(dataset_info.file_path)
            if dataset_info.file_size and actual_size != dataset_info.file_size:
                self.logger.warning(
                    f"File size mismatch for {dataset_info.dataset_id}: "
                    f"expected {dataset_info.file_size}, got {actual_size}"
                )

            # Basic format validation
            if not self._validate_file_format(dataset_info):
                return False

            return True

        except Exception as e:
            self.logger.error(f"Dataset validation failed for {dataset_info.dataset_id}: {e}")
            return False

    def _validate_file_format(self, dataset_info: DatasetInfo) -> bool:
        """Basic file format validation"""
        file_path = Path(dataset_info.file_path)

        # Check if file extension matches declared format
        actual_ext = file_path.suffix.lstrip('.').lower()
        declared_ext = dataset_info.file_ext.lower()

        if actual_ext != declared_ext:
            self.logger.warning(
                f"File extension mismatch for {dataset_info.dataset_id}: "
                f"file has {actual_ext}, declared as {declared_ext}"
            )

        # Format-specific validation
        if declared_ext in ['fasta', 'fa']:
            return self._validate_fasta_format(file_path)
        elif declared_ext in ['fastq', 'fq']:
            return self._validate_fastq_format(file_path)
        elif declared_ext in ['sam', 'bam']:
            return self._validate_sam_format(file_path)

        return True  # Default to valid for unknown formats

    def _validate_fasta_format(self, file_path: Path) -> bool:
        """Validate FASTA format"""
        try:
            with open(file_path, 'r') as f:
                first_line = f.readline().strip()
                return first_line.startswith('>')
        except Exception:
            return False

    def _validate_fastq_format(self, file_path: Path) -> bool:
        """Validate FASTQ format"""
        try:
            with open(file_path, 'r') as f:
                lines = [f.readline().strip() for _ in range(4)]
                return (
                    len(lines) == 4 and
                    lines[0].startswith('@') and
                    lines[2].startswith('+')
                )
        except Exception:
            return False

    def _validate_sam_format(self, file_path: Path) -> bool:
        """Validate SAM format"""
        try:
            with open(file_path, 'r') as f:
                for line in f:
                    line = line.strip()
                    if line.startswith('@'):
                        continue  # Header line
                    parts = line.split('\t')
                    return len(parts) >= 11  # SAM has at least 11 required fields
                return True
        except Exception:
            return False

    async def get_staging_summary(self) -> Dict[str, Any]:
        """Get summary of staged datasets"""
        return {
            'total_datasets': len(self.dataset_mappings),
            'staged_datasets': len([m for m in self.dataset_mappings.values() if m.staged]),
            'cache_size': len(self.staging_cache),
            'mappings': list(self.dataset_mappings.keys())
        }

    async def close(self):
        """Close all storage clients"""
        for client in self.storage_clients.values():
            await client.__aexit__(None, None, None)
        self.storage_clients.clear()