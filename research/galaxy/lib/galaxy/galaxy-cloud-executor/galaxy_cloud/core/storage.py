"""
Cloud storage abstraction layer.
Inspired by Nextflow's FileSystemPathFactory design.
"""

import asyncio
from abc import ABC, abstractmethod
from pathlib import Path
from typing import Dict, Any, Optional, List, AsyncIterator, Union
from urllib.parse import urlparse
import aiofiles
import aiofiles.os

from .auth import CloudAuth


class CloudPath:
    """
    Represents a path in cloud storage.
    Provides a unified interface for cloud storage operations.
    """
    
    def __init__(self, uri: str, storage: 'CloudStorage'):
        """
        Initialize a cloud path.
        
        Args:
            uri: Cloud storage URI (e.g., s3://bucket/key)
            storage: Cloud storage instance
        """
        self.uri = uri
        self.storage = storage
        self._parsed = urlparse(uri)
        
    @property
    def scheme(self) -> str:
        """Get the URI scheme (e.g., 's3', 'gs', 'az')."""
        return self._parsed.scheme
        
    @property
    def bucket(self) -> str:
        """Get the bucket/container name."""
        return self._parsed.netloc
        
    @property
    def key(self) -> str:
        """Get the object key/path."""
        return self._parsed.path.lstrip('/')
        
    @property
    def parent(self) -> 'CloudPath':
        """Get the parent path."""
        parent_key = '/'.join(self.key.split('/')[:-1])
        parent_uri = f"{self.scheme}://{self.bucket}/{parent_key}"
        return CloudPath(parent_uri, self.storage)
        
    @property
    def name(self) -> str:
        """Get the file/object name."""
        return self.key.split('/')[-1] if self.key else ''
        
    def __str__(self) -> str:
        return self.uri
        
    def __repr__(self) -> str:
        return f"CloudPath('{self.uri}')"
        
    def __truediv__(self, other: Union[str, 'CloudPath']) -> 'CloudPath':
        """Join path with another path component."""
        if isinstance(other, CloudPath):
            other = other.key
        new_key = f"{self.key.rstrip('/')}/{str(other).lstrip('/')}"
        new_uri = f"{self.scheme}://{self.bucket}/{new_key}"
        return CloudPath(new_uri, self.storage)
    
    async def exists(self) -> bool:
        """Check if the path exists."""
        return await self.storage.exists(self.uri)
        
    async def stat(self) -> Dict[str, Any]:
        """Get file/object statistics."""
        return await self.storage.stat(self.uri)
        
    async def read_bytes(self) -> bytes:
        """Read file content as bytes."""
        return await self.storage.read_bytes(self.uri)
        
    async def read_text(self, encoding: str = 'utf-8') -> str:
        """Read file content as text."""
        return await self.storage.read_text(self.uri, encoding)
        
    async def write_bytes(self, data: bytes) -> None:
        """Write bytes to the file."""
        await self.storage.write_bytes(self.uri, data)
        
    async def write_text(self, text: str, encoding: str = 'utf-8') -> None:
        """Write text to the file."""
        await self.storage.write_text(self.uri, text, encoding)
        
    async def upload_from(self, local_path: Union[str, Path]) -> None:
        """Upload a local file to this cloud path."""
        await self.storage.upload_file(str(local_path), self.uri)
        
    async def download_to(self, local_path: Union[str, Path]) -> None:
        """Download this cloud file to a local path."""
        await self.storage.download_file(self.uri, str(local_path))
        
    async def delete(self) -> None:
        """Delete the file/object."""
        await self.storage.delete(self.uri)
        
    async def list(self) -> AsyncIterator['CloudPath']:
        """List files in this directory/prefix."""
        async for uri in self.storage.list_files(self.uri):
            yield CloudPath(uri, self.storage)


class CloudStorage(ABC):
    """
    Abstract base class for cloud storage implementations.
    
    Inspired by Nextflow's FileSystemPathFactory pattern.
    """
    
    def __init__(self, config: Dict[str, Any], auth: Optional[CloudAuth] = None):
        """
        Initialize cloud storage.
        
        Args:
            config: Storage configuration
            auth: Authentication instance
        """
        self.config = config
        self.auth = auth
        self._initialized = False
    
    async def __aenter__(self):
        """Async context manager entry."""
        await self.initialize()
        return self
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager exit."""
        await self.cleanup()
    
    @abstractmethod
    async def initialize(self) -> None:
        """Initialize the storage client."""
        pass
    
    @abstractmethod
    async def cleanup(self) -> None:
        """Clean up storage resources."""
        pass
    
    @property
    @abstractmethod
    def scheme(self) -> str:
        """Return the URI scheme handled by this storage (e.g., 's3', 'gs', 'az')."""
        pass
    
    @abstractmethod
    def parse_uri(self, uri: str) -> Optional[CloudPath]:
        """
        Parse a URI and return a CloudPath if this storage can handle it.
        
        Args:
            uri: URI to parse
            
        Returns:
            CloudPath instance if URI is supported, None otherwise
        """
        pass
    
    @abstractmethod
    async def exists(self, uri: str) -> bool:
        """Check if a file/object exists."""
        pass
    
    @abstractmethod
    async def stat(self, uri: str) -> Dict[str, Any]:
        """Get file/object metadata."""
        pass
    
    @abstractmethod
    async def read_bytes(self, uri: str) -> bytes:
        """Read file content as bytes."""
        pass
    
    @abstractmethod
    async def write_bytes(self, uri: str, data: bytes) -> None:
        """Write bytes to a file."""
        pass
    
    @abstractmethod
    async def upload_file(self, local_path: str, remote_uri: str) -> None:
        """Upload a local file to cloud storage."""
        pass
    
    @abstractmethod
    async def download_file(self, remote_uri: str, local_path: str) -> None:
        """Download a file from cloud storage."""
        pass
    
    @abstractmethod
    async def delete(self, uri: str) -> None:
        """Delete a file/object."""
        pass
    
    @abstractmethod
    async def list_files(self, prefix_uri: str) -> AsyncIterator[str]:
        """List files with the given prefix."""
        pass
    
    async def read_text(self, uri: str, encoding: str = 'utf-8') -> str:
        """Read file content as text."""
        data = await self.read_bytes(uri)
        return data.decode(encoding)
    
    async def write_text(self, uri: str, text: str, encoding: str = 'utf-8') -> None:
        """Write text to a file."""
        data = text.encode(encoding)
        await self.write_bytes(uri, data)
    
    async def copy(self, source_uri: str, dest_uri: str) -> None:
        """
        Copy a file from source to destination.
        Default implementation downloads and uploads.
        """
        data = await self.read_bytes(source_uri)
        await self.write_bytes(dest_uri, data)
    
    async def sync_upload(self, local_dir: Path, remote_prefix: str) -> List[str]:
        """
        Sync a local directory to cloud storage.
        
        Args:
            local_dir: Local directory path
            remote_prefix: Remote prefix URI
            
        Returns:
            List of uploaded file URIs
        """
        uploaded_files = []
        
        if not local_dir.exists():
            raise FileNotFoundError(f"Local directory not found: {local_dir}")
        
        for local_file in local_dir.rglob('*'):
            if local_file.is_file():
                relative_path = local_file.relative_to(local_dir)
                remote_uri = f"{remote_prefix.rstrip('/')}/{relative_path}"
                
                await self.upload_file(str(local_file), remote_uri)
                uploaded_files.append(remote_uri)
        
        return uploaded_files
    
    async def sync_download(self, remote_prefix: str, local_dir: Path) -> List[str]:
        """
        Sync cloud storage to a local directory.
        
        Args:
            remote_prefix: Remote prefix URI
            local_dir: Local directory path
            
        Returns:
            List of downloaded file paths
        """
        downloaded_files = []
        
        # Ensure local directory exists
        local_dir.mkdir(parents=True, exist_ok=True)
        
        async for remote_uri in self.list_files(remote_prefix):
            # Calculate relative path
            relative_path = remote_uri[len(remote_prefix):].lstrip('/')
            local_file = local_dir / relative_path
            
            # Ensure parent directory exists
            local_file.parent.mkdir(parents=True, exist_ok=True)
            
            await self.download_file(remote_uri, str(local_file))
            downloaded_files.append(str(local_file))
        
        return downloaded_files
    
    async def bulk_upload(self, file_mappings: Dict[str, str]) -> List[str]:
        """
        Upload multiple files in parallel.
        
        Args:
            file_mappings: Dict mapping local paths to remote URIs
            
        Returns:
            List of successfully uploaded URIs
        """
        async def upload_single(local_path: str, remote_uri: str) -> Optional[str]:
            try:
                await self.upload_file(local_path, remote_uri)
                return remote_uri
            except Exception:
                return None
        
        tasks = [
            upload_single(local_path, remote_uri)
            for local_path, remote_uri in file_mappings.items()
        ]
        
        results = await asyncio.gather(*tasks, return_exceptions=True)
        return [uri for uri in results if uri is not None]
    
    async def bulk_download(self, file_mappings: Dict[str, str]) -> List[str]:
        """
        Download multiple files in parallel.
        
        Args:
            file_mappings: Dict mapping remote URIs to local paths
            
        Returns:
            List of successfully downloaded local paths
        """
        async def download_single(remote_uri: str, local_path: str) -> Optional[str]:
            try:
                await self.download_file(remote_uri, local_path)
                return local_path
            except Exception:
                return None
        
        tasks = [
            download_single(remote_uri, local_path)
            for remote_uri, local_path in file_mappings.items()
        ]
        
        results = await asyncio.gather(*tasks, return_exceptions=True)
        return [path for path in results if path is not None]