"""
Factory for creating cloud executors and storage providers.
Integrates with the registry system for dynamic provider creation.
"""

import logging
from typing import Dict, Any, Optional, Type

from .core.executor import CloudExecutor
from .core.storage import CloudStorage
from .core.auth import CloudAuth
from .config import CloudConfig
from .registry import registry, auto_register

logger = logging.getLogger(__name__)


class CloudExecutorFactory:
    """
    Factory for creating cloud executors.
    
    This factory integrates with the registry system to dynamically create
    executors based on registered providers.
    """
    
    @staticmethod
    @auto_register
    def create(
        executor_name: str, 
        config: Dict[str, Any],
        auth: Optional[CloudAuth] = None
    ) -> CloudExecutor:
        """
        Create a cloud executor instance.
        
        Args:
            executor_name: Name of the executor (e.g., 'aws-batch', 'azure-batch')
            config: Executor configuration
            auth: Optional authentication instance
            
        Returns:
            Initialized executor instance
            
        Raises:
            ValueError: If executor is not found or creation fails
        """
        executor_class = registry.get_executor(executor_name)
        
        if executor_class is None:
            available = registry.list_executors()
            raise ValueError(
                f"Executor '{executor_name}' not found. "
                f"Available executors: {', '.join(available)}"
            )
        
        try:
            # Create executor with config and optional auth
            if auth:
                return executor_class(config, auth=auth)
            else:
                return executor_class(config)
        except Exception as e:
            raise ValueError(f"Failed to create executor '{executor_name}': {str(e)}")
    
    @staticmethod
    def list_available() -> Dict[str, Dict[str, Any]]:
        """
        List all available executors with their metadata.
        
        Returns:
            Dictionary mapping executor names to metadata
        """
        result = {}
        for name in registry.list_executors():
            metadata = registry.get_metadata('executor', name)
            result[name] = metadata
        return result
    
    @staticmethod
    def is_available(executor_name: str) -> bool:
        """
        Check if an executor is available.
        
        Args:
            executor_name: Name of the executor
            
        Returns:
            True if available, False otherwise
        """
        return registry.is_executor_available(executor_name)


class CloudStorageFactory:
    """
    Factory for creating cloud storage providers.
    """
    
    @staticmethod
    @auto_register
    def create(
        scheme: str, 
        config: Dict[str, Any],
        auth: Optional[CloudAuth] = None
    ) -> CloudStorage:
        """
        Create a cloud storage instance.
        
        Args:
            scheme: URI scheme (e.g., 's3', 'gs', 'az')
            config: Storage configuration
            auth: Optional authentication instance
            
        Returns:
            Initialized storage instance
            
        Raises:
            ValueError: If storage provider is not found or creation fails
        """
        storage_class = registry.get_storage(scheme)
        
        if storage_class is None:
            available = registry.list_storage_schemes()
            raise ValueError(
                f"Storage provider for scheme '{scheme}' not found. "
                f"Available schemes: {', '.join(available)}"
            )
        
        try:
            # Create storage with config and optional auth
            if auth:
                return storage_class(config, auth=auth)
            else:
                return storage_class(config)
        except Exception as e:
            raise ValueError(f"Failed to create storage provider for '{scheme}': {str(e)}")
    
    @staticmethod
    def create_from_uri(
        uri: str, 
        config: Dict[str, Any],
        auth: Optional[CloudAuth] = None
    ) -> CloudStorage:
        """
        Create a storage provider based on URI scheme.
        
        Args:
            uri: URI to determine scheme from
            config: Storage configuration
            auth: Optional authentication instance
            
        Returns:
            Initialized storage instance
            
        Raises:
            ValueError: If URI scheme is not supported
        """
        from urllib.parse import urlparse
        
        parsed = urlparse(uri)
        if not parsed.scheme:
            raise ValueError(f"Invalid URI: {uri}")
        
        return CloudStorageFactory.create(parsed.scheme, config, auth)
    
    @staticmethod
    def list_available() -> Dict[str, Dict[str, Any]]:
        """
        List all available storage providers with their metadata.
        
        Returns:
            Dictionary mapping schemes to metadata
        """
        result = {}
        for scheme in registry.list_storage_schemes():
            metadata = registry.get_metadata('storage', scheme)
            result[scheme] = metadata
        return result
    
    @staticmethod
    def is_available(scheme: str) -> bool:
        """
        Check if a storage provider is available.
        
        Args:
            scheme: URI scheme
            
        Returns:
            True if available, False otherwise
        """
        return registry.is_storage_available(scheme)


class CloudAuthFactory:
    """
    Factory for creating cloud authentication providers.
    """
    
    @staticmethod
    @auto_register
    def create(provider: str, config: Dict[str, Any]) -> CloudAuth:
        """
        Create a cloud authentication instance.
        
        Args:
            provider: Provider name (e.g., 'aws', 'azure', 'gcp')
            config: Authentication configuration
            
        Returns:
            Initialized authentication instance
            
        Raises:
            ValueError: If auth provider is not found or creation fails
        """
        auth_class = registry.get_auth(provider)
        
        if auth_class is None:
            available = registry.list_auth_providers()
            raise ValueError(
                f"Auth provider '{provider}' not found. "
                f"Available providers: {', '.join(available)}"
            )
        
        try:
            return auth_class(config)
        except Exception as e:
            raise ValueError(f"Failed to create auth provider '{provider}': {str(e)}")
    
    @staticmethod
    def list_available() -> Dict[str, Dict[str, Any]]:
        """
        List all available auth providers with their metadata.
        
        Returns:
            Dictionary mapping provider names to metadata
        """
        result = {}
        for provider in registry.list_auth_providers():
            metadata = registry.get_metadata('auth', provider)
            result[provider] = metadata
        return result
    
    @staticmethod
    def is_available(provider: str) -> bool:
        """
        Check if an auth provider is available.
        
        Args:
            provider: Provider name
            
        Returns:
            True if available, False otherwise
        """
        return registry.is_auth_available(provider)


class CloudProviderFactory:
    """
    High-level factory for creating complete cloud provider setups.
    """
    
    @staticmethod
    def create_from_config(
        provider_name: str, 
        cloud_config: CloudConfig
    ) -> Dict[str, Any]:
        """
        Create a complete cloud provider setup from configuration.
        
        Args:
            provider_name: Provider name ('aws', 'azure', 'gcp', 'kubernetes')
            cloud_config: Complete cloud configuration
            
        Returns:
            Dictionary containing executor, storage, and auth instances
            
        Raises:
            ValueError: If provider is not configured or available
        """
        # Get provider-specific configuration
        provider_config = cloud_config.get_provider_config(provider_name)
        if not provider_config or not provider_config.enabled:
            raise ValueError(f"Provider '{provider_name}' is not enabled in configuration")
        
        result = {}
        
        # Create authentication if available
        auth = None
        if CloudAuthFactory.is_available(provider_name):
            try:
                auth = CloudAuthFactory.create(provider_name, provider_config.dict())
                result['auth'] = auth
            except Exception as e:
                logger.warning(f"Failed to create auth for {provider_name}: {e}")
        
        # Create executor
        executor_name = CloudProviderFactory._get_executor_name(provider_name)
        if CloudExecutorFactory.is_available(executor_name):
            try:
                executor = CloudExecutorFactory.create(
                    executor_name, 
                    provider_config.dict(), 
                    auth
                )
                result['executor'] = executor
            except Exception as e:
                logger.warning(f"Failed to create executor for {provider_name}: {e}")
        
        # Create storage
        storage_scheme = CloudProviderFactory._get_storage_scheme(provider_name)
        if CloudStorageFactory.is_available(storage_scheme):
            try:
                storage = CloudStorageFactory.create(
                    storage_scheme, 
                    provider_config.dict(), 
                    auth
                )
                result['storage'] = storage
            except Exception as e:
                logger.warning(f"Failed to create storage for {provider_name}: {e}")
        
        if not result:
            raise ValueError(f"No components available for provider '{provider_name}'")
        
        return result
    
    @staticmethod
    def create_all_enabled(cloud_config: CloudConfig) -> Dict[str, Dict[str, Any]]:
        """
        Create all enabled cloud providers from configuration.
        
        Args:
            cloud_config: Complete cloud configuration
            
        Returns:
            Dictionary mapping provider names to their components
        """
        result = {}
        
        for provider_name in cloud_config.get_enabled_providers():
            try:
                components = CloudProviderFactory.create_from_config(
                    provider_name, 
                    cloud_config
                )
                result[provider_name] = components
            except Exception as e:
                logger.warning(f"Failed to create provider {provider_name}: {e}")
        
        return result
    
    @staticmethod
    def _get_executor_name(provider_name: str) -> str:
        """Get the default executor name for a provider."""
        executor_mapping = {
            'aws': 'aws-batch',
            'azure': 'azure-batch',
            'gcp': 'google-batch',
            'kubernetes': 'k8s'
        }
        return executor_mapping.get(provider_name, f"{provider_name}-batch")
    
    @staticmethod
    def _get_storage_scheme(provider_name: str) -> str:
        """Get the default storage scheme for a provider."""
        scheme_mapping = {
            'aws': 's3',
            'azure': 'az',
            'gcp': 'gs',
            'kubernetes': 'pv'  # Persistent volume
        }
        return scheme_mapping.get(provider_name, provider_name)
    
    @staticmethod
    def get_provider_status() -> Dict[str, Dict[str, bool]]:
        """
        Get the availability status of all providers.
        
        Returns:
            Dictionary with provider availability information
        """
        providers = ['aws', 'azure', 'gcp', 'kubernetes']
        result = {}
        
        for provider in providers:
            executor_name = CloudProviderFactory._get_executor_name(provider)
            storage_scheme = CloudProviderFactory._get_storage_scheme(provider)
            
            result[provider] = {
                'executor_available': CloudExecutorFactory.is_available(executor_name),
                'storage_available': CloudStorageFactory.is_available(storage_scheme),
                'auth_available': CloudAuthFactory.is_available(provider)
            }
        
        return result