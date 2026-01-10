"""
AWS S3 storage implementation.
Inspired by Nextflow's S3FileSystemProvider and S3PathFactory.
"""

from __future__ import annotations

import asyncio
import logging
from typing import Dict, Any, Optional, AsyncIterator, Tuple
from urllib.parse import urlparse
from pathlib import Path

try:
    import boto3
    import aioboto3
    from botocore.exceptions import ClientError, NoCredentialsError
    BOTO3_AVAILABLE = True
except ImportError:
    BOTO3_AVAILABLE = False

from ...core.storage import CloudStorage, CloudPath
from ...core.auth import CloudAuth
from ...registry import cloud_storage
from .auth import AWSAuth

logger = logging.getLogger(__name__)


@cloud_storage("s3", metadata={"requires": ["boto3", "aioboto3"], "description": "AWS S3 storage implementation"})
class S3Storage(CloudStorage):
    """
    AWS S3 storage implementation using aioboto3 for async operations.
    
    Inspired by Nextflow's S3 integration with the following features:
    - Async file operations
    - Large file multipart upload/download
    - Intelligent retry with exponential backoff
    - Support for S3-compatible services
    """
    
    def __init__(self, config: Dict[str, Any], auth: Optional[CloudAuth] = None):
        """
        Initialize S3 storage.
        
        Args:
            config: S3 storage configuration
            auth: Optional AWS authentication instance
        """
        super().__init__(config, auth)
        
        if not BOTO3_AVAILABLE:
            raise ImportError("boto3 and aioboto3 are required for S3 storage. Install with: pip install boto3 aioboto3")
        
        self._session: Optional[aioboto3.Session] = None
        self._sync_session: Optional[boto3.Session] = None
        
        # S3 configuration
        self.bucket = config.get('bucket') or config.get('s3_bucket')
        self.prefix = config.get('prefix', config.get('s3_prefix', ''))
        self.endpoint_url = config.get('endpoint_url')
        self.use_ssl = config.get('use_ssl', True)
        self.region = config.get('region', 'us-east-1')
        
        # Transfer configuration
        self.multipart_threshold = config.get('multipart_threshold', 64 * 1024 * 1024)  # 64MB
        self.max_concurrency = config.get('max_concurrency', 10)
        self.max_bandwidth = config.get('max_bandwidth')  # bytes per second
    
    async def initialize(self) -> None:
        """Initialize S3 storage."""
        # Get credentials from auth if available
        if isinstance(self.auth, AWSAuth):
            await self.auth.initialize()
            credentials = await self.auth.get_credentials()
            
            # Create async session with credentials
            self._session = aioboto3.Session(
                aws_access_key_id=credentials.get('access_key_id'),
                aws_secret_access_key=credentials.get('secret_access_key'),
                aws_session_token=credentials.get('session_token'),
                region_name=self.region
            )
            
            # Create sync session for non-async operations
            self._sync_session = boto3.Session(
                aws_access_key_id=credentials.get('access_key_id'),
                aws_secret_access_key=credentials.get('secret_access_key'),
                aws_session_token=credentials.get('session_token'),
                region_name=self.region
            )
        else:
            # Use default credential chain
            self._session = aioboto3.Session(region_name=self.region)
            self._sync_session = boto3.Session(region_name=self.region)
        
        # Test connection
        await self._test_connection()
        self._initialized = True
    
    async def cleanup(self) -> None:
        """Clean up S3 storage."""
        self._session = None
        self._sync_session = None
        if self.auth:
            await self.auth.cleanup()
        self._initialized = False
    
    @property
    def scheme(self) -> str:
        """Return the URI scheme."""
        return "s3"
    
    def parse_uri(self, uri: str) -> Optional[CloudPath]:
        """
        Parse an S3 URI and return a CloudPath if supported.
        
        Args:
            uri: URI to parse (e.g., s3://bucket/key)
            
        Returns:
            CloudPath instance if URI is s3://, None otherwise
        """
        if not uri.startswith('s3://'):
            return None
        
        return CloudPath(uri, self)
    
    def _parse_s3_uri(self, uri: str) -> tuple[str, str]:
        """
        Parse S3 URI into bucket and key components.
        
        Args:
            uri: S3 URI
            
        Returns:
            Tuple of (bucket, key)
        """
        parsed = urlparse(uri)
        if parsed.scheme != 's3':
            raise ValueError(f"Invalid S3 URI: {uri}")
        
        bucket = parsed.netloc
        key = parsed.path.lstrip('/')
        
        return bucket, key
    
    async def _get_client(self):
        """Get an async S3 client."""
        if not self._session:
            raise RuntimeError("S3 storage not initialized")
        
        client_kwargs = {}
        if self.endpoint_url:
            client_kwargs['endpoint_url'] = self.endpoint_url
        if not self.use_ssl:
            client_kwargs['use_ssl'] = False
        
        return self._session.client('s3', **client_kwargs)
    
    async def _test_connection(self) -> None:
        """Test S3 connection."""
        async with await self._get_client() as s3:
            try:
                # List buckets to test connection
                await s3.list_buckets()
            except Exception as e:
                raise RuntimeError(f"Failed to connect to S3: {e}")
    
    async def exists(self, uri: str) -> bool:
        """Check if an S3 object exists."""
        bucket, key = self._parse_s3_uri(uri)
        
        if not key:  # Bucket-only URI
            return await self._bucket_exists(bucket)
        
        async with await self._get_client() as s3:
            try:
                await s3.head_object(Bucket=bucket, Key=key)
                return True
            except ClientError as e:
                if e.response['Error']['Code'] == '404':
                    return False
                raise
    
    async def _bucket_exists(self, bucket: str) -> bool:
        """Check if a bucket exists."""
        async with await self._get_client() as s3:
            try:
                await s3.head_bucket(Bucket=bucket)
                return True
            except ClientError as e:
                if e.response['Error']['Code'] in ['404', 'NoSuchBucket']:
                    return False
                raise
    
    async def stat(self, uri: str) -> Dict[str, Any]:
        """Get S3 object metadata."""
        bucket, key = self._parse_s3_uri(uri)
        
        async with await self._get_client() as s3:
            try:
                response = await s3.head_object(Bucket=bucket, Key=key)
                return {
                    'size': response.get('ContentLength', 0),
                    'last_modified': response.get('LastModified'),
                    'etag': response.get('ETag', '').strip('\"'),
                    'content_type': response.get('ContentType'),
                    'metadata': response.get('Metadata', {}),
                    'storage_class': response.get('StorageClass', 'STANDARD'),
                }
            except ClientError as e:
                if e.response['Error']['Code'] == '404':
                    raise FileNotFoundError(f"S3 object not found: {uri}")
                raise
    
    async def read_bytes(self, uri: str) -> bytes:
        """Read S3 object content as bytes."""
        bucket, key = self._parse_s3_uri(uri)
        
        async with await self._get_client() as s3:
            try:
                response = await s3.get_object(Bucket=bucket, Key=key)
                async with response['Body'] as stream:
                    return await stream.read()
            except ClientError as e:
                if e.response['Error']['Code'] == '404':
                    raise FileNotFoundError(f"S3 object not found: {uri}")
                raise
    
    async def write_bytes(self, uri: str, data: bytes) -> None:
        """Write bytes to an S3 object."""
        bucket, key = self._parse_s3_uri(uri)
        
        async with await self._get_client() as s3:
            await s3.put_object(Bucket=bucket, Key=key, Body=data)
    
    async def upload_file(self, local_path: str, remote_uri: str) -> None:
        """
        Upload a local file to S3.
        
        Uses multipart upload for large files automatically.
        """
        bucket, key = self._parse_s3_uri(remote_uri)
        local_file = Path(local_path)
        
        if not local_file.exists():
            raise FileNotFoundError(f"Local file not found: {local_path}")
        
        # Use sync client for file upload with transfer manager
        def _upload():
            s3_client = self._sync_session.client('s3')
            
            # Configure transfer
            from boto3.s3.transfer import TransferConfig
            config = TransferConfig(
                multipart_threshold=self.multipart_threshold,
                max_concurrency=self.max_concurrency,
                max_bandwidth=self.max_bandwidth,
                use_threads=True
            )
            
            s3_client.upload_file(
                str(local_file), 
                bucket, 
                key,
                Config=config
            )
        
        # Run in thread pool
        loop = asyncio.get_event_loop()
        await loop.run_in_executor(None, _upload)
    
    async def download_file(self, remote_uri: str, local_path: str) -> None:
        """
        Download an S3 object to a local file.
        
        Uses multipart download for large files automatically.
        """
        bucket, key = self._parse_s3_uri(remote_uri)
        local_file = Path(local_path)
        
        # Ensure parent directory exists
        local_file.parent.mkdir(parents=True, exist_ok=True)
        
        # Use sync client for file download with transfer manager
        def _download():
            s3_client = self._sync_session.client('s3')
            
            # Configure transfer
            from boto3.s3.transfer import TransferConfig
            config = TransferConfig(
                multipart_threshold=self.multipart_threshold,
                max_concurrency=self.max_concurrency,
                max_bandwidth=self.max_bandwidth,
                use_threads=True
            )
            
            s3_client.download_file(
                bucket, 
                key, 
                str(local_file),
                Config=config
            )
        
        # Run in thread pool
        loop = asyncio.get_event_loop()
        await loop.run_in_executor(None, _download)
    
    async def delete(self, uri: str) -> None:
        """Delete an S3 object."""
        bucket, key = self._parse_s3_uri(uri)
        
        async with await self._get_client() as s3:
            await s3.delete_object(Bucket=bucket, Key=key)
    
    async def list_files(self, prefix_uri: str) -> AsyncIterator[str]:
        """
        List S3 objects with the given prefix.
        
        Args:
            prefix_uri: S3 URI prefix
            
        Yields:
            S3 URIs of matching objects
        """
        bucket, prefix = self._parse_s3_uri(prefix_uri)
        
        async with await self._get_client() as s3:
            paginator = s3.get_paginator('list_objects_v2')
            
            async for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
                for obj in page.get('Contents', []):
                    yield f"s3://{bucket}/{obj['Key']}"
    
    async def copy(self, source_uri: str, dest_uri: str) -> None:
        """
        Copy an S3 object from source to destination.
        
        Uses S3-native copy operation for efficiency.
        """
        source_bucket, source_key = self._parse_s3_uri(source_uri)
        dest_bucket, dest_key = self._parse_s3_uri(dest_uri)
        
        copy_source = {'Bucket': source_bucket, 'Key': source_key}
        
        async with await self._get_client() as s3:
            await s3.copy_object(
                CopySource=copy_source,
                Bucket=dest_bucket,
                Key=dest_key
            )
    
    async def sync_directory(
        self, 
        local_dir: Path, 
        remote_prefix: str, 
        delete_extra: bool = False
    ) -> Dict[str, Any]:
        """
        Sync a local directory to S3.
        
        Args:
            local_dir: Local directory to sync
            remote_prefix: S3 prefix to sync to
            delete_extra: Whether to delete extra S3 objects
            
        Returns:
            Sync statistics
        """
        if not local_dir.exists():
            raise FileNotFoundError(f"Local directory not found: {local_dir}")
        
        bucket, prefix = self._parse_s3_uri(remote_prefix)
        
        uploaded = []
        skipped = []
        errors = []
        
        # Upload local files
        for local_file in local_dir.rglob('*'):
            if local_file.is_file():
                relative_path = local_file.relative_to(local_dir)
                s3_key = f"{prefix.rstrip('/')}/{relative_path}".replace('\\', '/')
                s3_uri = f"s3://{bucket}/{s3_key}"
                
                try:
                    # Check if file needs to be uploaded
                    should_upload = True
                    if await self.exists(s3_uri):
                        # Compare modification times or sizes
                        s3_stat = await self.stat(s3_uri)
                        local_stat = local_file.stat()
                        
                        if s3_stat['size'] == local_stat.st_size:
                            should_upload = False
                    
                    if should_upload:
                        await self.upload_file(str(local_file), s3_uri)
                        uploaded.append(s3_uri)
                    else:
                        skipped.append(s3_uri)
                        
                except Exception as e:
                    errors.append({'file': str(local_file), 'error': str(e)})
        
        # Optionally delete extra S3 objects
        deleted = []
        if delete_extra:
            local_keys = set()
            for local_file in local_dir.rglob('*'):
                if local_file.is_file():
                    relative_path = local_file.relative_to(local_dir)
                    s3_key = f"{prefix.rstrip('/')}/{relative_path}".replace('\\', '/')
                    local_keys.add(s3_key)
            
            async for s3_uri in self.list_files(remote_prefix):
                _, s3_key = self._parse_s3_uri(s3_uri)
                if s3_key not in local_keys:
                    try:
                        await self.delete(s3_uri)
                        deleted.append(s3_uri)
                    except Exception as e:
                        errors.append({'file': s3_uri, 'error': str(e)})
        
        return {
            'uploaded': len(uploaded),
            'skipped': len(skipped),
            'deleted': len(deleted),
            'errors': len(errors),
            'uploaded_files': uploaded,
            'skipped_files': skipped,
            'deleted_files': deleted,
            'error_details': errors,
        }