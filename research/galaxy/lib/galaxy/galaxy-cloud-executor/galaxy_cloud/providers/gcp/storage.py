"""
Google Cloud Storage implementation.
"""

import asyncio
import mimetypes
from typing import Dict, Any, Optional, AsyncIterator
from pathlib import Path
from urllib.parse import urlparse
from datetime import datetime, timedelta

from google.cloud import storage
from google.cloud.storage import Blob, Bucket
from google.api_core import exceptions as gcp_exceptions
from google.resumable_media import InvalidResponse

from galaxy_cloud.core.storage import CloudStorage, CloudPath
from galaxy_cloud.registry import cloud_storage
from galaxy_cloud.providers.gcp.auth import GCPAuth


@cloud_storage("gcs", {
    "description": "Google Cloud Storage provider",
    "supported_features": [
        "versioning", "lifecycle_management", "encryption",
        "uniform_bucket_level_access", "signed_urls", "cors",
        "object_retention", "event_notifications"
    ],
    "version": "1.0.0"
})
class GCSStorage(CloudStorage):
    """Google Cloud Storage implementation."""
    
    def __init__(self, config: Dict[str, Any], **kwargs):
        super().__init__(config, **kwargs)
        
        # GCS configuration
        self.project_id = config.get('project_id')
        self.bucket_name = config.get('bucket_name', 'galaxy-data')
        self.location = config.get('location', 'US')
        
        # Storage class configuration
        self.storage_class = config.get('storage_class', 'STANDARD')
        
        # Performance settings
        self.chunk_size = config.get('chunk_size', 256 * 1024)  # 256KB chunks
        self.max_retry_delay = config.get('max_retry_delay', 60)
        self.max_cumulative_retry = config.get('max_cumulative_retry', 120)
        
        # Transfer settings
        self.resumable_threshold = config.get('resumable_threshold', 8 * 1024 * 1024)  # 8MB
        self.max_workers = config.get('max_workers', 8)
        
        # Encryption settings
        self.encryption_key = config.get('encryption_key')  # Customer-supplied encryption key
        self.kms_key_name = config.get('kms_key_name')      # Cloud KMS key
        
        # Access control
        self.predefined_acl = config.get('predefined_acl')
        self.uniform_bucket_level_access = config.get('uniform_bucket_level_access', True)
        
        # Signed URL settings
        self.signed_url_expiration_hours = config.get('signed_url_expiration_hours', 24)
        
        # Internal state
        self.gcs_client: Optional[storage.Client] = None
        self.auth_provider: Optional[GCPAuth] = None
        
    async def initialize(self) -> None:
        """Initialize Google Cloud Storage client."""
        self.auth_provider = GCPAuth(self.config)
        await self.auth_provider.initialize()
        
        # Get GCP credentials
        credentials = await self.auth_provider.get_credentials()
        
        # Initialize GCS client
        self.gcs_client = storage.Client(
            project=self.project_id,
            credentials=credentials.raw_credentials
        )
        
        # Ensure bucket exists
        await self._ensure_bucket()
        
        self._initialized = True
        self.logger.info(f"GCS Storage initialized for project: {self.project_id}, bucket: {self.bucket_name}")
    
    async def cleanup(self) -> None:
        """Clean up GCS resources."""
        if self.gcs_client:
            self.gcs_client.close()
            
        if self.auth_provider:
            await self.auth_provider.cleanup()
        
        self._initialized = False
        self.logger.info("GCS Storage cleaned up")
    
    @property
    def scheme(self) -> str:
        return "gcs"
    
    def parse_uri(self, uri: str) -> Optional[CloudPath]:
        """Parse Google Cloud Storage URI."""
        if not uri.startswith(('gcs://', 'gs://', 'https://storage.googleapis.com/')):
            return None
        
        if uri.startswith('https://storage.googleapis.com/'):
            # Handle https://storage.googleapis.com/bucket/path format
            parsed = urlparse(uri)
            path_parts = parsed.path.strip('/').split('/', 1)
            if len(path_parts) < 2:
                return None
            
            bucket = path_parts[0]
            object_path = path_parts[1]
            
            # Convert to gcs:// format
            gcs_uri = f"gcs://{bucket}/{object_path}"
            return CloudPath(gcs_uri, self)
        
        else:
            # Handle gcs://bucket/path or gs://bucket/path format
            if uri.startswith('gs://'):
                uri = uri.replace('gs://', 'gcs://', 1)
            return CloudPath(uri, self)
    
    def _parse_gcs_uri(self, uri: str) -> tuple[str, str]:
        """Parse GCS URI into bucket and object path."""
        if uri.startswith('gcs://'):
            path = uri[6:]  # Remove gcs://
        elif uri.startswith('gs://'):
            path = uri[5:]   # Remove gs://
        else:
            raise ValueError(f"Invalid GCS URI format: {uri}")
        
        if '/' not in path:
            return path, ''
        
        parts = path.split('/', 1)
        return parts[0], parts[1]
    
    async def exists(self, uri: str) -> bool:
        """Check if object exists in GCS."""
        try:
            bucket_name, object_name = self._parse_gcs_uri(uri)
            
            if not object_name:
                # Check if bucket exists
                bucket = self.gcs_client.bucket(bucket_name)
                return await asyncio.to_thread(bucket.exists)
            else:
                # Check if object exists
                bucket = self.gcs_client.bucket(bucket_name)
                blob = bucket.blob(object_name)
                return await asyncio.to_thread(blob.exists)
                
        except Exception as e:
            self.logger.error(f"Failed to check existence of {uri}: {e}")
            return False
    
    async def stat(self, uri: str) -> Dict[str, Any]:
        """Get object metadata and properties."""
        try:
            bucket_name, object_name = self._parse_gcs_uri(uri)
            
            if not object_name:
                # Get bucket properties
                bucket = self.gcs_client.bucket(bucket_name)
                await asyncio.to_thread(bucket.reload)
                
                return {
                    'type': 'bucket',
                    'name': bucket_name,
                    'created': bucket.time_created,
                    'updated': bucket.updated,
                    'location': bucket.location,
                    'storage_class': bucket.storage_class,
                    'versioning_enabled': bucket.versioning_enabled,
                    'lifecycle_rules': len(bucket.lifecycle_rules) if bucket.lifecycle_rules else 0,
                    'labels': bucket.labels or {},
                    'metageneration': bucket.metageneration
                }
            else:
                # Get object properties
                bucket = self.gcs_client.bucket(bucket_name)
                blob = bucket.blob(object_name)
                await asyncio.to_thread(blob.reload)
                
                return {
                    'type': 'object',
                    'name': object_name,
                    'bucket': bucket_name,
                    'size': blob.size,
                    'created': blob.time_created,
                    'updated': blob.updated,
                    'content_type': blob.content_type,
                    'content_encoding': blob.content_encoding,
                    'etag': blob.etag,
                    'md5_hash': blob.md5_hash,
                    'crc32c': blob.crc32c,
                    'storage_class': blob.storage_class,
                    'generation': blob.generation,
                    'metageneration': blob.metageneration,
                    'metadata': blob.metadata or {},
                    'custom_time': blob.custom_time,
                    'temporary_hold': blob.temporary_hold,
                    'event_based_hold': blob.event_based_hold
                }
                
        except Exception as e:
            self.logger.error(f"Failed to get properties for {uri}: {e}")
            raise
    
    async def read_bytes(self, uri: str) -> bytes:
        """Read object content as bytes."""
        try:
            bucket_name, object_name = self._parse_gcs_uri(uri)
            
            bucket = self.gcs_client.bucket(bucket_name)
            blob = bucket.blob(object_name)
            
            content = await asyncio.to_thread(blob.download_as_bytes)
            
            return content
            
        except Exception as e:
            self.logger.error(f"Failed to read {uri}: {e}")
            raise
    
    async def write_bytes(self, uri: str, data: bytes) -> None:
        """Write bytes to GCS object."""
        try:
            bucket_name, object_name = self._parse_gcs_uri(uri)
            
            bucket = self.gcs_client.bucket(bucket_name)
            blob = bucket.blob(object_name)
            
            # Set content type
            content_type = mimetypes.guess_type(object_name)[0] or 'application/octet-stream'
            blob.content_type = content_type
            
            # Set storage class
            blob.storage_class = self.storage_class
            
            # Set encryption if configured
            if self.encryption_key:
                blob.encryption_key = self.encryption_key
            elif self.kms_key_name:
                blob.kms_key_name = self.kms_key_name
            
            # Upload data
            await asyncio.to_thread(blob.upload_from_string, data)
            
            self.logger.debug(f"Uploaded {len(data)} bytes to {uri}")
            
        except Exception as e:
            self.logger.error(f"Failed to write to {uri}: {e}")
            raise
    
    async def upload_file(self, local_path: str, remote_uri: str, **kwargs) -> None:
        """Upload file to Google Cloud Storage."""
        try:
            local_file = Path(local_path)
            if not local_file.exists():
                raise FileNotFoundError(f"Local file not found: {local_path}")
            
            bucket_name, object_name = self._parse_gcs_uri(remote_uri)
            
            bucket = self.gcs_client.bucket(bucket_name)
            blob = bucket.blob(object_name)
            
            # Set content type
            content_type = mimetypes.guess_type(local_path)[0] or 'application/octet-stream'
            blob.content_type = content_type
            
            # Set storage class
            blob.storage_class = self.storage_class
            
            # Set encryption if configured
            if self.encryption_key:
                blob.encryption_key = self.encryption_key
            elif self.kms_key_name:
                blob.kms_key_name = self.kms_key_name
            
            # Upload with resumable uploads for large files
            file_size = local_file.stat().st_size
            
            if file_size > self.resumable_threshold:
                # Use resumable upload for large files
                await asyncio.to_thread(
                    blob.upload_from_filename,
                    local_path,
                    chunk_size=self.chunk_size
                )
            else:
                # Simple upload for small files
                await asyncio.to_thread(blob.upload_from_filename, local_path)
            
            self.logger.info(f"Uploaded {local_path} ({file_size} bytes) to {remote_uri}")
            
        except Exception as e:
            self.logger.error(f"Failed to upload {local_path} to {remote_uri}: {e}")
            raise
    
    async def download_file(self, remote_uri: str, local_path: str, **kwargs) -> None:
        """Download file from Google Cloud Storage."""
        try:
            bucket_name, object_name = self._parse_gcs_uri(remote_uri)
            
            bucket = self.gcs_client.bucket(bucket_name)
            blob = bucket.blob(object_name)
            
            # Ensure local directory exists
            local_file = Path(local_path)
            local_file.parent.mkdir(parents=True, exist_ok=True)
            
            # Download with resumable downloads for large files
            blob_size = await asyncio.to_thread(lambda: blob.reload() or blob.size)
            
            if blob_size and blob_size > self.resumable_threshold:
                # Use resumable download for large files
                await asyncio.to_thread(
                    blob.download_to_filename,
                    local_path,
                    chunk_size=self.chunk_size
                )
            else:
                # Simple download for small files
                await asyncio.to_thread(blob.download_to_filename, local_path)
            
            file_size = local_file.stat().st_size
            self.logger.info(f"Downloaded {remote_uri} to {local_path} ({file_size} bytes)")
            
        except Exception as e:
            self.logger.error(f"Failed to download {remote_uri} to {local_path}: {e}")
            raise
    
    async def delete(self, uri: str) -> None:
        """Delete object or bucket."""
        try:
            bucket_name, object_name = self._parse_gcs_uri(uri)
            
            if not object_name:
                # Delete bucket
                bucket = self.gcs_client.bucket(bucket_name)
                await asyncio.to_thread(bucket.delete)
                self.logger.info(f"Deleted bucket: {bucket_name}")
            else:
                # Delete object
                bucket = self.gcs_client.bucket(bucket_name)
                blob = bucket.blob(object_name)
                await asyncio.to_thread(blob.delete)
                self.logger.info(f"Deleted object: {uri}")
                
        except Exception as e:
            self.logger.error(f"Failed to delete {uri}: {e}")
            raise
    
    async def list_files(self, prefix_uri: str, recursive: bool = True) -> AsyncIterator[str]:
        """List objects with given prefix."""
        try:
            bucket_name, object_prefix = self._parse_gcs_uri(prefix_uri)
            
            bucket = self.gcs_client.bucket(bucket_name)
            
            # Configure listing options
            delimiter = None if recursive else '/'
            
            blobs = await asyncio.to_thread(
                lambda: list(bucket.list_blobs(prefix=object_prefix, delimiter=delimiter))
            )
            
            for blob in blobs:
                yield f"gcs://{bucket_name}/{blob.name}"
                
        except Exception as e:
            self.logger.error(f"Failed to list files with prefix {prefix_uri}: {e}")
            raise
    
    async def copy_file(self, source_uri: str, dest_uri: str, **kwargs) -> None:
        """Copy object within GCS or from external source."""
        try:
            dest_bucket_name, dest_object_name = self._parse_gcs_uri(dest_uri)
            dest_bucket = self.gcs_client.bucket(dest_bucket_name)
            dest_blob = dest_bucket.blob(dest_object_name)
            
            if source_uri.startswith('gcs://'):
                # Server-side copy within GCS
                source_bucket_name, source_object_name = self._parse_gcs_uri(source_uri)
                source_bucket = self.gcs_client.bucket(source_bucket_name)
                source_blob = source_bucket.blob(source_object_name)
                
                # Copy blob
                await asyncio.to_thread(source_bucket.copy_blob, source_blob, dest_bucket, dest_object_name)
                
                self.logger.info(f"Copied {source_uri} to {dest_uri}")
            else:
                # Copy from external source (download then upload)
                if source_uri.startswith(('http://', 'https://')):
                    # Download from URL and upload to GCS
                    import aiohttp
                    
                    async with aiohttp.ClientSession() as session:
                        async with session.get(source_uri) as response:
                            if response.status == 200:
                                content = await response.read()
                                await self.write_bytes(dest_uri, content)
                            else:
                                raise RuntimeError(f"Failed to download from {source_uri}: HTTP {response.status}")
                else:
                    raise ValueError(f"Unsupported source URI format: {source_uri}")
                
        except Exception as e:
            self.logger.error(f"Failed to copy {source_uri} to {dest_uri}: {e}")
            raise
    
    async def generate_presigned_url(self, uri: str, expiry_hours: int = None, method: str = 'GET') -> str:
        """Generate signed URL for object access."""
        try:
            bucket_name, object_name = self._parse_gcs_uri(uri)
            
            if expiry_hours is None:
                expiry_hours = self.signed_url_expiration_hours
            
            bucket = self.gcs_client.bucket(bucket_name)
            blob = bucket.blob(object_name)
            
            # Calculate expiration time
            expiration = datetime.utcnow() + timedelta(hours=expiry_hours)
            
            # Generate signed URL
            signed_url = await asyncio.to_thread(
                blob.generate_signed_url,
                expiration=expiration,
                method=method,
                version='v4'
            )
            
            return signed_url
            
        except Exception as e:
            self.logger.error(f"Failed to generate signed URL for {uri}: {e}")
            raise
    
    async def sync_upload(self, local_dir: Path, remote_prefix: str, **kwargs) -> None:
        """Synchronize local directory to GCS."""
        try:
            local_path = Path(local_dir)
            if not local_path.is_dir():
                raise ValueError(f"Local path is not a directory: {local_dir}")
            
            # Get all local files
            local_files = []
            for file_path in local_path.rglob('*'):
                if file_path.is_file():
                    relative_path = file_path.relative_to(local_path)
                    local_files.append((file_path, relative_path))
            
            # Upload files with controlled concurrency
            semaphore = asyncio.Semaphore(self.max_workers)
            
            async def upload_file(local_file_path: Path, relative_path: Path):
                async with semaphore:
                    remote_path = remote_prefix.rstrip('/') + '/' + str(relative_path).replace('\\', '/')
                    await self.upload_file(str(local_file_path), remote_path)
            
            tasks = [
                upload_file(local_file_path, relative_path)
                for local_file_path, relative_path in local_files
            ]
            
            await asyncio.gather(*tasks)
            
            self.logger.info(f"Synchronized {len(local_files)} files from {local_dir} to {remote_prefix}")
            
        except Exception as e:
            self.logger.error(f"Failed to sync upload {local_dir} to {remote_prefix}: {e}")
            raise
    
    async def sync_download(self, remote_prefix: str, local_dir: Path, **kwargs) -> None:
        """Synchronize GCS to local directory."""
        try:
            local_path = Path(local_dir)
            local_path.mkdir(parents=True, exist_ok=True)
            
            # List all remote files
            remote_files = []
            async for object_uri in self.list_files(remote_prefix):
                _, object_name = self._parse_gcs_uri(object_uri)
                if object_name.startswith(self._parse_gcs_uri(remote_prefix)[1]):
                    # Calculate relative path
                    prefix_path = self._parse_gcs_uri(remote_prefix)[1]
                    relative_path = object_name[len(prefix_path):].lstrip('/')
                    remote_files.append((object_uri, relative_path))
            
            # Download files with controlled concurrency
            semaphore = asyncio.Semaphore(self.max_workers)
            
            async def download_file(remote_uri: str, relative_path: str):
                async with semaphore:
                    local_file_path = local_path / relative_path
                    await self.download_file(remote_uri, str(local_file_path))
            
            tasks = [
                download_file(remote_uri, relative_path)
                for remote_uri, relative_path in remote_files
            ]
            
            await asyncio.gather(*tasks)
            
            self.logger.info(f"Synchronized {len(remote_files)} files from {remote_prefix} to {local_dir}")
            
        except Exception as e:
            self.logger.error(f"Failed to sync download {remote_prefix} to {local_dir}: {e}")
            raise
    
    # Advanced GCS features
    
    async def set_object_metadata(self, uri: str, metadata: Dict[str, str]) -> None:
        """Set custom metadata on object."""
        try:
            bucket_name, object_name = self._parse_gcs_uri(uri)
            
            bucket = self.gcs_client.bucket(bucket_name)
            blob = bucket.blob(object_name)
            
            blob.metadata = metadata
            await asyncio.to_thread(blob.patch)
            
            self.logger.info(f"Set metadata on {uri}: {metadata}")
            
        except Exception as e:
            self.logger.error(f"Failed to set metadata on {uri}: {e}")
            raise
    
    async def set_object_acl(self, uri: str, entity: str, role: str) -> None:
        """Set object access control."""
        try:
            bucket_name, object_name = self._parse_gcs_uri(uri)
            
            bucket = self.gcs_client.bucket(bucket_name)
            blob = bucket.blob(object_name)
            
            await asyncio.to_thread(blob.acl.entity, entity, role)
            await asyncio.to_thread(blob.acl.save)
            
            self.logger.info(f"Set ACL on {uri}: {entity} = {role}")
            
        except Exception as e:
            self.logger.error(f"Failed to set ACL on {uri}: {e}")
            raise
    
    async def enable_versioning(self, bucket_name: str = None) -> None:
        """Enable versioning on bucket."""
        try:
            bucket_name = bucket_name or self.bucket_name
            bucket = self.gcs_client.bucket(bucket_name)
            
            bucket.versioning_enabled = True
            await asyncio.to_thread(bucket.patch)
            
            self.logger.info(f"Enabled versioning on bucket: {bucket_name}")
            
        except Exception as e:
            self.logger.error(f"Failed to enable versioning on {bucket_name}: {e}")
            raise
    
    async def set_lifecycle_rule(self, bucket_name: str = None, **rule_config) -> None:
        """Set lifecycle management rule on bucket."""
        try:
            bucket_name = bucket_name or self.bucket_name
            bucket = self.gcs_client.bucket(bucket_name)
            
            # Example lifecycle rule configuration
            rule = {
                'action': rule_config.get('action', {'type': 'Delete'}),
                'condition': rule_config.get('condition', {'age': 30})
            }
            
            bucket.add_lifecycle_delete_rule(**rule_config)
            await asyncio.to_thread(bucket.patch)
            
            self.logger.info(f"Set lifecycle rule on bucket: {bucket_name}")
            
        except Exception as e:
            self.logger.error(f"Failed to set lifecycle rule on {bucket_name}: {e}")
            raise
    
    # Helper methods
    
    async def _ensure_bucket(self) -> None:
        """Ensure the bucket exists."""
        try:
            bucket = self.gcs_client.bucket(self.bucket_name)
            await asyncio.to_thread(bucket.reload)
            self.logger.info(f"Using existing GCS bucket: {self.bucket_name}")
            
        except gcp_exceptions.NotFound:
            # Create bucket
            bucket = self.gcs_client.bucket(self.bucket_name)
            bucket.storage_class = self.storage_class
            bucket.location = self.location
            
            if self.uniform_bucket_level_access:
                bucket.iam_configuration.uniform_bucket_level_access_enabled = True
            
            await asyncio.to_thread(self.gcs_client.create_bucket, bucket)
            self.logger.info(f"Created GCS bucket: {self.bucket_name}")
    
    def get_bucket(self, bucket_name: str = None) -> Bucket:
        """Get bucket client for direct operations."""
        bucket_name = bucket_name or self.bucket_name
        return self.gcs_client.bucket(bucket_name)
    
    def get_blob(self, object_name: str, bucket_name: str = None) -> Blob:
        """Get blob client for direct operations."""
        bucket_name = bucket_name or self.bucket_name
        bucket = self.gcs_client.bucket(bucket_name)
        return bucket.blob(object_name)