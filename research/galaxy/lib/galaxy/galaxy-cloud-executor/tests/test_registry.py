"""
Tests for plugin registry and discovery mechanism.
"""

import pytest
from typing import Dict, Any, Optional, List, AsyncIterator

from galaxy_cloud.registry import (
    ProviderRegistry, 
    registry,
    cloud_executor,
    cloud_storage, 
    cloud_auth,
    get_available_providers,
    validate_provider_availability,
    ensure_providers_available
)
from galaxy_cloud.core.executor import CloudExecutor
from galaxy_cloud.core.storage import CloudStorage, CloudPath
from galaxy_cloud.core.auth import CloudAuth
from galaxy_cloud.core.job import JobSpec, JobStatus, JobResult


# Mock implementations for testing

class MockExecutor(CloudExecutor):
    """Mock executor for testing."""
    
    def __init__(self, config: Dict[str, Any], **kwargs):
        super().__init__(config, **kwargs)
    
    async def initialize(self) -> None:
        self._initialized = True
    
    async def cleanup(self) -> None:
        self._initialized = False
    
    @property
    def provider_name(self) -> str:
        return "mock"
    
    @property
    def executor_type(self) -> str:
        return "test"
    
    async def submit_job(self, job_spec: JobSpec) -> str:
        return "mock-job-123"
    
    async def get_job_status(self, cloud_job_id: str) -> JobStatus:
        return JobStatus.COMPLETED
    
    async def get_job_result(self, cloud_job_id: str) -> JobResult:
        return JobResult(
            job_id=cloud_job_id,
            cloud_job_id=cloud_job_id,
            status=JobStatus.COMPLETED
        )
    
    async def cancel_job(self, cloud_job_id: str) -> bool:
        return True
    
    async def list_jobs(self, status_filter: Optional[JobStatus] = None) -> List[str]:
        return ["mock-job-123"]


class MockStorage(CloudStorage):
    """Mock storage for testing."""
    
    async def initialize(self) -> None:
        self._initialized = True
    
    async def cleanup(self) -> None:
        self._initialized = False
    
    @property
    def scheme(self) -> str:
        return "mock"
    
    def parse_uri(self, uri: str) -> Optional[CloudPath]:
        if uri.startswith('mock://'):
            return CloudPath(uri, self)
        return None
    
    async def exists(self, uri: str) -> bool:
        return True
    
    async def stat(self, uri: str) -> Dict[str, Any]:
        return {"size": 1024, "modified": "2023-01-01"}
    
    async def read_bytes(self, uri: str) -> bytes:
        return b"mock data"
    
    async def write_bytes(self, uri: str, data: bytes) -> None:
        pass
    
    async def upload_file(self, local_path: str, remote_uri: str) -> None:
        pass
    
    async def download_file(self, remote_uri: str, local_path: str) -> None:
        pass
    
    async def delete(self, uri: str) -> None:
        pass
    
    async def list_files(self, prefix_uri: str) -> AsyncIterator[str]:
        yield "mock://bucket/file1.txt"
        yield "mock://bucket/file2.txt"


class MockAuth(CloudAuth):
    """Mock authentication for testing."""
    
    async def initialize(self) -> None:
        self._initialized = True
    
    async def cleanup(self) -> None:
        self._initialized = False
    
    @property
    def provider_name(self) -> str:
        return "mock"
    
    async def get_credentials(self, force_refresh: bool = False):
        from galaxy_cloud.core.auth import CloudCredentials
        return CloudCredentials({"mock_token": "abc123"})
    
    async def refresh_credentials(self):
        return await self.get_credentials()


class TestProviderRegistry:
    """Test ProviderRegistry functionality."""
    
    def setup_method(self):
        """Setup for each test method."""
        # Create a fresh registry for each test
        self.test_registry = ProviderRegistry()
    
    def test_register_executor(self):
        """Test executor registration."""
        self.test_registry.register_executor('mock-executor', MockExecutor)
        
        assert self.test_registry.is_executor_available('mock-executor')
        assert 'mock-executor' in self.test_registry.list_executors()
        
        executor_class = self.test_registry.get_executor('mock-executor')
        assert executor_class == MockExecutor
    
    def test_register_executor_with_metadata(self):
        """Test executor registration with metadata."""
        metadata = {"description": "Mock executor for testing", "version": "1.0"}
        self.test_registry.register_executor('mock-executor', MockExecutor, metadata)
        
        stored_metadata = self.test_registry.get_metadata('executor', 'mock-executor')
        assert stored_metadata == metadata
    
    def test_register_storage(self):
        """Test storage provider registration."""
        self.test_registry.register_storage('mock', MockStorage)
        
        assert self.test_registry.is_storage_available('mock')
        assert 'mock' in self.test_registry.list_storage_schemes()
        
        storage_class = self.test_registry.get_storage('mock')
        assert storage_class == MockStorage
    
    def test_register_auth(self):
        """Test auth provider registration."""
        self.test_registry.register_auth('mock', MockAuth)
        
        assert self.test_registry.is_auth_available('mock')
        assert 'mock' in self.test_registry.list_auth_providers()
        
        auth_class = self.test_registry.get_auth('mock')
        assert auth_class == MockAuth
    
    def test_invalid_registrations(self):
        """Test registration of invalid classes."""
        class NotAnExecutor:
            pass
        
        with pytest.raises(ValueError, match="must inherit from CloudExecutor"):
            self.test_registry.register_executor('invalid', NotAnExecutor)
        
        with pytest.raises(ValueError, match="must inherit from CloudStorage"):
            self.test_registry.register_storage('invalid', NotAnExecutor)
        
        with pytest.raises(ValueError, match="must inherit from CloudAuth"):
            self.test_registry.register_auth('invalid', NotAnExecutor)
    
    def test_get_nonexistent_providers(self):
        """Test getting non-existent providers."""
        assert self.test_registry.get_executor('nonexistent') is None
        assert self.test_registry.get_storage('nonexistent') is None
        assert self.test_registry.get_auth('nonexistent') is None
    
    def test_registry_status(self):
        """Test registry status reporting."""
        # Empty registry
        status = self.test_registry.status()
        assert status['executors'] == 0
        assert status['storage_providers'] == 0
        assert status['auth_providers'] == 0
        
        # Add some providers
        self.test_registry.register_executor('mock-executor', MockExecutor)
        self.test_registry.register_storage('mock', MockStorage)
        self.test_registry.register_auth('mock', MockAuth)
        
        status = self.test_registry.status()
        assert status['executors'] == 1
        assert status['storage_providers'] == 1
        assert status['auth_providers'] == 1
        assert 'mock-executor' in status['executor_names']
        assert 'mock' in status['storage_schemes']
        assert 'mock' in status['auth_providers']
    
    def test_clear_registry(self):
        """Test clearing the registry."""
        # Add providers
        self.test_registry.register_executor('mock-executor', MockExecutor)
        self.test_registry.register_storage('mock', MockStorage)
        self.test_registry.register_auth('mock', MockAuth)
        
        # Verify they exist
        assert self.test_registry.is_executor_available('mock-executor')
        assert self.test_registry.is_storage_available('mock')
        assert self.test_registry.is_auth_available('mock')
        
        # Clear
        self.test_registry.clear()
        
        # Verify they're gone
        assert not self.test_registry.is_executor_available('mock-executor')
        assert not self.test_registry.is_storage_available('mock')
        assert not self.test_registry.is_auth_available('mock')


class TestRegistryDecorators:
    """Test registry decorator functions."""
    
    def setup_method(self):
        """Setup for each test method."""
        # Clear global registry
        registry.clear()
    
    def test_cloud_executor_decorator(self):
        """Test @cloud_executor decorator."""
        @cloud_executor("decorated-executor")
        class DecoratedExecutor(MockExecutor):
            pass
        
        assert registry.is_executor_available("decorated-executor")
        executor_class = registry.get_executor("decorated-executor")
        assert executor_class == DecoratedExecutor
        assert hasattr(DecoratedExecutor, '_registry_executor_name')
        assert DecoratedExecutor._registry_executor_name == "decorated-executor"
    
    def test_cloud_storage_decorator(self):
        """Test @cloud_storage decorator."""
        @cloud_storage("decorated")
        class DecoratedStorage(MockStorage):
            pass
        
        assert registry.is_storage_available("decorated")
        storage_class = registry.get_storage("decorated")
        assert storage_class == DecoratedStorage
        assert hasattr(DecoratedStorage, '_registry_storage_scheme')
        assert DecoratedStorage._registry_storage_scheme == "decorated"
    
    def test_cloud_auth_decorator(self):
        """Test @cloud_auth decorator."""
        @cloud_auth("decorated")
        class DecoratedAuth(MockAuth):
            pass
        
        assert registry.is_auth_available("decorated")
        auth_class = registry.get_auth("decorated")
        assert auth_class == DecoratedAuth
        assert hasattr(DecoratedAuth, '_registry_auth_provider')
        assert DecoratedAuth._registry_auth_provider == "decorated"
    
    def test_decorator_with_metadata(self):
        """Test decorators with metadata."""
        metadata = {"test": "metadata"}
        
        @cloud_executor("meta-executor", metadata)
        class MetaExecutor(MockExecutor):
            pass
        
        stored_metadata = registry.get_metadata('executor', 'meta-executor')
        assert stored_metadata == metadata
        assert hasattr(MetaExecutor, '_registry_metadata')
        assert MetaExecutor._registry_metadata == metadata


class TestUtilityFunctions:
    """Test utility functions."""
    
    def setup_method(self):
        """Setup for each test method."""
        registry.clear()
        # Register test providers
        registry.register_executor('test-executor', MockExecutor)
        registry.register_storage('test', MockStorage)
        registry.register_auth('test', MockAuth)
    
    def test_get_available_providers(self):
        """Test get_available_providers function."""
        providers = get_available_providers()
        
        assert 'executors' in providers
        assert 'storage' in providers
        assert 'auth' in providers
        
        assert 'test-executor' in providers['executors']
        assert 'test' in providers['storage']
        assert 'test' in providers['auth']
    
    def test_validate_provider_availability(self):
        """Test validate_provider_availability function."""
        # Test available providers
        result = validate_provider_availability(
            executor='test-executor',
            storage='test',
            auth='test'
        )
        
        assert result['executor'] is True
        assert result['storage'] is True
        assert result['auth'] is True
        
        # Test unavailable providers
        result = validate_provider_availability(
            executor='nonexistent',
            storage='nonexistent',
            auth='nonexistent'
        )
        
        assert result['executor'] is False
        assert result['storage'] is False
        assert result['auth'] is False
    
    def test_ensure_providers_available_success(self):
        """Test ensure_providers_available with available providers."""
        # Should not raise an exception
        ensure_providers_available(
            'executor:test-executor',
            'storage:test',
            'auth:test'
        )
    
    def test_ensure_providers_available_failure(self):
        """Test ensure_providers_available with unavailable providers."""
        with pytest.raises(ValueError, match="Required providers not available"):
            ensure_providers_available(
                'executor:nonexistent',
                'storage:test'
            )
    
    def test_ensure_providers_available_invalid_spec(self):
        """Test ensure_providers_available with invalid spec format."""
        with pytest.raises(ValueError, match="Invalid provider spec"):
            ensure_providers_available('invalid-spec')
        
        with pytest.raises(ValueError, match="Unknown provider type"):
            ensure_providers_available('unknown:provider')


class TestAutoDiscovery:
    """Test auto-discovery functionality."""
    
    def setup_method(self):
        """Setup for each test method."""
        self.test_registry = ProviderRegistry()
    
    def test_auto_discover_nonexistent_packages(self):
        """Test auto-discovery with non-existent packages."""
        # Should not raise an exception
        self.test_registry.auto_discover(['nonexistent.package'])
        
        # Registry should still be empty
        status = self.test_registry.status()
        assert status['executors'] == 0
        assert status['storage_providers'] == 0
        assert status['auth_providers'] == 0
    
    def test_discover_package_attributes(self):
        """Test package discovery with mock attributes."""
        # This would require more complex mocking of importlib
        # For now, just test that the method doesn't crash
        self.test_registry._discover_package('galaxy_cloud.core')
        
        # Should complete without error
        assert True