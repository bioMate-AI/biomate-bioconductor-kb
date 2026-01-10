"""
Azure Blob Storage implementation.
"""

import asyncio
import mimetypes
from typing import Dict, Any, Optional, AsyncIterator
from pathlib import Path
from urllib.parse import urlparse

from azure.storage.blob.aio import BlobServiceClient, BlobClient
from azure.storage.blob import BlobSasPermissions, generate_blob_sas
from azure.core.exceptions import ResourceNotFoundError
from azure.identity.aio import DefaultAzureCredential

from galaxy_cloud.core.storage import CloudStorage, CloudPath
from galaxy_cloud.registry import cloud_storage
from galaxy_cloud.providers.azure.auth import AzureAuth


@cloud_storage("azblob", {
    "description": "Azure Blob Storage provider",
    "supported_features": [
        "hierarchical_namespace", "encryption", "versioning",
        "lifecycle_management", "access_tiers", "sas_tokens"
    ],
    "version": "1.0.0"
})
class AzureBlobStorage(CloudStorage):
    """Azure Blob Storage implementation."""
    
    def __init__(self, config: Dict[str, Any], **kwargs):
        super().__init__(config, **kwargs)
        
        # Azure Storage configuration
        self.account_name = config.get('storage_account')
        self.account_url = config.get('account_url') or f"https://{self.account_name}.blob.core.windows.net"
        self.container_name = config.get('container_name', 'galaxy-data')
        
        # Access configuration
        self.access_tier = config.get('access_tier', 'Hot')
        self.encryption_scope = config.get('encryption_scope')
        
        # Performance settings
        self.max_concurrency = config.get('max_concurrency', 4)
        self.chunk_size = config.get('chunk_size', 4 * 1024 * 1024)  # 4MB chunks
        
        # SAS token settings
        self.sas_token_expiry_hours = config.get('sas_token_expiry_hours', 24)
        
        # Internal state
        self.blob_service_client: Optional[BlobServiceClient] = None
        self.auth_provider: Optional[AzureAuth] = None
        
    async def initialize(self) -> None:
        """Initialize Azure Blob Storage client."""
        self.auth_provider = AzureAuth(self.config)
        await self.auth_provider.initialize()
        
        # Get Azure credentials
        credentials = await self.auth_provider.get_credentials()
        
        # Initialize Blob service client
        self.blob_service_client = BlobServiceClient(
            account_url=self.account_url,
            credential=credentials.raw_credentials
        )
        
        # Ensure container exists
        await self._ensure_container()
        
        self._initialized = True
        self.logger.info(f"Azure Blob Storage initialized for account: {self.account_name}")
    
    async def cleanup(self) -> None:
        """Clean up Azure Blob Storage resources."""
        if self.blob_service_client:
            await self.blob_service_client.close()
        
        if self.auth_provider:
            await self.auth_provider.cleanup()
        
        self._initialized = False
        self.logger.info("Azure Blob Storage cleaned up")
    
    @property
    def scheme(self) -> str:
        return "azblob"
    
    def parse_uri(self, uri: str) -> Optional[CloudPath]:
        """Parse Azure Blob Storage URI."""
        if not uri.startswith(('azblob://', 'az://', 'https://')):
            return None
        
        if uri.startswith('https://'):
            # Handle https://account.blob.core.windows.net/container/path format
            parsed = urlparse(uri)
            if '.blob.core.windows.net' not in parsed.netloc:
                return None
            
            path_parts = parsed.path.strip('/').split('/', 1)
            if len(path_parts) < 2:
                return None
            
            container = path_parts[0]
            blob_path = path_parts[1]
            
            # Convert to azblob:// format
            azblob_uri = f"azblob://{container}/{blob_path}"
            return CloudPath(azblob_uri, self)
        
        else:
            # Handle azblob://container/path or az://container/path format
            if uri.startswith('az://'):
                uri = uri.replace('az://', 'azblob://', 1)
            return CloudPath(uri, self)
    
    def _parse_azblob_uri(self, uri: str) -> tuple[str, str]:
        """Parse azblob URI into container and blob path."""
        if uri.startswith('azblob://'):
            path = uri[9:]  # Remove azblob://
        elif uri.startswith('az://'):
            path = uri[5:]  # Remove az://
        else:
            raise ValueError(f"Invalid Azure Blob URI format: {uri}")
        
        if '/' not in path:
            return path, ''
        
        parts = path.split('/', 1)
        return parts[0], parts[1]
    
    async def exists(self, uri: str) -> bool:
        """Check if blob exists."""
        try:
            container_name, blob_name = self._parse_azblob_uri(uri)
            
            if not blob_name:
                # Check if container exists
                container_client = self.blob_service_client.get_container_client(container_name)
                try:
                    await container_client.get_container_properties()
                    return True
                except ResourceNotFoundError:
                    return False
            else:
                # Check if blob exists
                blob_client = self.blob_service_client.get_blob_client(
                    container=container_name,
                    blob=blob_name
                )
                try:
                    await blob_client.get_blob_properties()
                    return True
                except ResourceNotFoundError:
                    return False
                    
        except Exception as e:
            self.logger.error(f"Failed to check existence of {uri}: {e}")
            return False
    
    async def stat(self, uri: str) -> Dict[str, Any]:
        """Get blob metadata and properties."""
        try:
            container_name, blob_name = self._parse_azblob_uri(uri)
            
            if not blob_name:
                # Get container properties
                container_client = self.blob_service_client.get_container_client(container_name)
                properties = await container_client.get_container_properties()
                
                return {
                    'type': 'container',
                    'name': container_name,
                    'created': properties.creation_time,
                    'modified': properties.last_modified,
                    'etag': properties.etag,
                    'metadata': properties.metadata or {}
                }
            else:
                # Get blob properties
                blob_client = self.blob_service_client.get_blob_client(
                    container=container_name,
                    blob=blob_name
                )
                properties = await blob_client.get_blob_properties()
                
                return {
                    'type': 'blob',
                    'name': blob_name,
                    'size': properties.size,
                    'created': properties.creation_time,
                    'modified': properties.last_modified,
                    'etag': properties.etag,
                    'content_type': properties.content_settings.content_type,
                    'content_encoding': properties.content_settings.content_encoding,
                    'access_tier': properties.blob_tier,
                    'metadata': properties.metadata or {},
                    'tags': properties.tag_count
                }
                
        except Exception as e:
            self.logger.error(f"Failed to get properties for {uri}: {e}")
            raise
    
    async def read_bytes(self, uri: str) -> bytes:
        """Read blob content as bytes."""
        try:
            container_name, blob_name = self._parse_azblob_uri(uri)
            
            blob_client = self.blob_service_client.get_blob_client(
                container=container_name,
                blob=blob_name
            )
            
            download_stream = await blob_client.download_blob()
            content = await download_stream.readall()
            
            return content
            
        except Exception as e:
            self.logger.error(f"Failed to read {uri}: {e}")
            raise
    
    async def write_bytes(self, uri: str, data: bytes) -> None:
        """Write bytes to blob."""
        try:
            container_name, blob_name = self._parse_azblob_uri(uri)
            
            blob_client = self.blob_service_client.get_blob_client(
                container=container_name,
                blob=blob_name
            )
            
            # Determine content type
            content_type = mimetypes.guess_type(blob_name)[0] or 'application/octet-stream'
            
            await blob_client.upload_blob(
                data,
                blob_type='BlockBlob',
                content_settings={
                    'content_type': content_type
                },
                standard_blob_tier=self.access_tier,
                encryption_scope=self.encryption_scope,
                overwrite=True,
                max_concurrency=self.max_concurrency
            )
            
            self.logger.debug(f"Uploaded {len(data)} bytes to {uri}")
            
        except Exception as e:
            self.logger.error(f"Failed to write to {uri}: {e}")
            raise
    
    async def upload_file(self, local_path: str, remote_uri: str, **kwargs) -> None:
        """Upload file to Azure Blob Storage."""
        try:
            local_file = Path(local_path)
            if not local_file.exists():
                raise FileNotFoundError(f"Local file not found: {local_path}")
            
            container_name, blob_name = self._parse_azblob_uri(remote_uri)
            
            blob_client = self.blob_service_client.get_blob_client(
                container=container_name,
                blob=blob_name
            )
            
            # Determine content type
            content_type = mimetypes.guess_type(local_path)[0] or 'application/octet-stream'
            
            # Upload with streaming
            with open(local_path, 'rb') as data:
                await blob_client.upload_blob(
                    data,
                    blob_type='BlockBlob',
                    content_settings={
                        'content_type': content_type
                    },
                    standard_blob_tier=self.access_tier,
                    encryption_scope=self.encryption_scope,
                    overwrite=True,
                    max_concurrency=self.max_concurrency
                )
            
            file_size = local_file.stat().st_size
            self.logger.info(f"Uploaded {local_path} ({file_size} bytes) to {remote_uri}")
            
        except Exception as e:
            self.logger.error(f"Failed to upload {local_path} to {remote_uri}: {e}")
            raise
    
    async def download_file(self, remote_uri: str, local_path: str, **kwargs) -> None:
        """Download file from Azure Blob Storage."""
        try:
            container_name, blob_name = self._parse_azblob_uri(remote_uri)
            
            blob_client = self.blob_service_client.get_blob_client(
                container=container_name,
                blob=blob_name
            )
            
            # Ensure local directory exists
            local_file = Path(local_path)
            local_file.parent.mkdir(parents=True, exist_ok=True)
            
            # Download with streaming
            with open(local_path, 'wb') as download_file:
                download_stream = await blob_client.download_blob(
                    max_concurrency=self.max_concurrency
                )
                async for chunk in download_stream.chunks():
                    download_file.write(chunk)
            
            file_size = local_file.stat().st_size
            self.logger.info(f"Downloaded {remote_uri} to {local_path} ({file_size} bytes)")
            
        except Exception as e:
            self.logger.error(f"Failed to download {remote_uri} to {local_path}: {e}")
            raise
    
    async def delete(self, uri: str) -> None:
        """Delete blob or container."""
        try:
            container_name, blob_name = self._parse_azblob_uri(uri)
            
            if not blob_name:
                # Delete container
                container_client = self.blob_service_client.get_container_client(container_name)
                await container_client.delete_container()
                self.logger.info(f"Deleted container: {container_name}")
            else:
                # Delete blob
                blob_client = self.blob_service_client.get_blob_client(
                    container=container_name,
                    blob=blob_name
                )
                await blob_client.delete_blob()
                self.logger.info(f"Deleted blob: {uri}")
                
        except Exception as e:
            self.logger.error(f"Failed to delete {uri}: {e}")
            raise
    
    async def list_files(self, prefix_uri: str, recursive: bool = True) -> AsyncIterator[str]:
        """List blobs with given prefix."""
        try:
            container_name, blob_prefix = self._parse_azblob_uri(prefix_uri)
            
            container_client = self.blob_service_client.get_container_client(container_name)
            
            async for blob in container_client.list_blobs(name_starts_with=blob_prefix):
                if not recursive and '/' in blob.name[len(blob_prefix):].lstrip('/'):
                    continue
                
                yield f"azblob://{container_name}/{blob.name}"
                
        except Exception as e:
            self.logger.error(f"Failed to list files with prefix {prefix_uri}: {e}")
            raise
    
    async def copy_file(self, source_uri: str, dest_uri: str, **kwargs) -> None:
        """Copy blob within Azure Storage or from external source."""
        try:
            dest_container, dest_blob = self._parse_azblob_uri(dest_uri)
            
            dest_blob_client = self.blob_service_client.get_blob_client(
                container=dest_container,
                blob=dest_blob
            )
            
            if source_uri.startswith('azblob://'):
                # Server-side copy within Azure Storage
                source_container, source_blob = self._parse_azblob_uri(source_uri)
                source_blob_client = self.blob_service_client.get_blob_client(
                    container=source_container,
                    blob=source_blob
                )
                
                # Get source blob URL
                source_url = source_blob_client.url
                
                # Start copy operation
                copy_props = await dest_blob_client.start_copy_from_url(source_url)
                
                # Wait for copy to complete
                while copy_props['copy_status'] == 'pending':
                    await asyncio.sleep(1)
                    props = await dest_blob_client.get_blob_properties()
                    copy_props = props.copy
                
                if copy_props['copy_status'] != 'success':
                    raise RuntimeError(f"Copy failed: {copy_props.get('copy_status_description', 'Unknown error')}")
                
                self.logger.info(f"Copied {source_uri} to {dest_uri}")
            else:
                # Copy from external source (download then upload)
                if source_uri.startswith(('http://', 'https://')):
                    # Copy from HTTP URL
                    copy_props = await dest_blob_client.start_copy_from_url(source_uri)
                    
                    while copy_props['copy_status'] == 'pending':
                        await asyncio.sleep(1)
                        props = await dest_blob_client.get_blob_properties()
                        copy_props = props.copy
                    
                    if copy_props['copy_status'] != 'success':
                        raise RuntimeError(f"Copy failed: {copy_props.get('copy_status_description', 'Unknown error')}")
                else:
                    raise ValueError(f"Unsupported source URI format: {source_uri}")
                
        except Exception as e:
            self.logger.error(f"Failed to copy {source_uri} to {dest_uri}: {e}")
            raise
    
    async def generate_presigned_url(self, uri: str, expiry_hours: int = None, permissions: str = 'r') -> str:
        """Generate SAS URL for blob access."""
        try:
            container_name, blob_name = self._parse_azblob_uri(uri)
            
            if expiry_hours is None:
                expiry_hours = self.sas_token_expiry_hours
            
            # Map permissions
            permission_map = {
                'r': BlobSasPermissions.read,
                'w': BlobSasPermissions.write,
                'rw': BlobSasPermissions.read | BlobSasPermissions.write,
                'read': BlobSasPermissions.read,
                'write': BlobSasPermissions.write,
                'full': BlobSasPermissions.read | BlobSasPermissions.write | BlobSasPermissions.delete
            }
            
            sas_permissions = permission_map.get(permissions.lower(), BlobSasPermissions.read)
            
            # Generate SAS token
            from datetime import datetime, timedelta, timezone
            
            sas_token = generate_blob_sas(
                account_name=self.account_name,
                container_name=container_name,
                blob_name=blob_name,
                account_key=None,  # Will use credential from auth provider
                permission=sas_permissions,
                expiry=datetime.now(timezone.utc) + timedelta(hours=expiry_hours)
            )
            
            # Construct full URL
            blob_url = f"https://{self.account_name}.blob.core.windows.net/{container_name}/{blob_name}?{sas_token}"
            
            return blob_url
            
        except Exception as e:
            self.logger.error(f"Failed to generate presigned URL for {uri}: {e}")
            raise
    
    async def sync_upload(self, local_dir: Path, remote_prefix: str, **kwargs) -> None:
        """Synchronize local directory to Azure Blob Storage."""
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
            
            # Upload files concurrently
            semaphore = asyncio.Semaphore(self.max_concurrency)
            
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
        """Synchronize Azure Blob Storage to local directory."""
        try:
            local_path = Path(local_dir)
            local_path.mkdir(parents=True, exist_ok=True)
            
            # List all remote files
            remote_files = []
            async for blob_uri in self.list_files(remote_prefix):
                _, blob_name = self._parse_azblob_uri(blob_uri)
                if blob_name.startswith(self._parse_azblob_uri(remote_prefix)[1]):
                    # Calculate relative path
                    prefix_path = self._parse_azblob_uri(remote_prefix)[1]
                    relative_path = blob_name[len(prefix_path):].lstrip('/')
                    remote_files.append((blob_uri, relative_path))
            
            # Download files concurrently
            semaphore = asyncio.Semaphore(self.max_concurrency)
            
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
    
    # Helper methods
    
    async def _ensure_container(self) -> None:
        """Ensure the container exists."""
        try:
            container_client = self.blob_service_client.get_container_client(self.container_name)
            await container_client.get_container_properties()
            self.logger.info(f"Using existing Azure Blob container: {self.container_name}")
            
        except ResourceNotFoundError:
            # Create container
            container_client = self.blob_service_client.get_container_client(self.container_name)
            await container_client.create_container()
            self.logger.info(f"Created Azure Blob container: {self.container_name}")
    
    async def get_container_client(self, container_name: str = None):
        """Get container client for direct operations."""
        container = container_name or self.container_name
        return self.blob_service_client.get_container_client(container)
    
    async def get_blob_client(self, blob_name: str, container_name: str = None):
        """Get blob client for direct operations."""
        container = container_name or self.container_name
        return self.blob_service_client.get_blob_client(
            container=container,
            blob=blob_name
        )