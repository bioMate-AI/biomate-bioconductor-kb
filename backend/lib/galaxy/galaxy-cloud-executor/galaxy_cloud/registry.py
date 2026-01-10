"""
Plugin registry and discovery mechanism.
Inspired by Nextflow's plugin system and PF4J framework.
"""

import logging
import importlib
import inspect
from typing import Dict, Type, Optional, List, Any, Callable
from functools import wraps

from .core.executor import CloudExecutor
from .core.storage import CloudStorage
from .core.auth import CloudAuth

logger = logging.getLogger(__name__)


class ProviderRegistry:
    """
    Central registry for cloud providers and their components.
    
    This class manages the registration and discovery of:
    - Cloud executors
    - Storage providers
    - Authentication providers
    """
    
    def __init__(self):
        """Initialize the registry."""
        self._executors: Dict[str, Type[CloudExecutor]] = {}
        self._storage_providers: Dict[str, Type[CloudStorage]] = {}
        self._auth_providers: Dict[str, Type[CloudAuth]] = {}
        self._metadata: Dict[str, Dict[str, Any]] = {}
        self._initialized = False
    
    def register_executor(
        self, 
        name: str, 
        executor_class: Type[CloudExecutor],
        metadata: Optional[Dict[str, Any]] = None
    ) -> None:
        """
        Register a cloud executor.
        
        Args:
            name: Executor name (e.g., 'aws-batch', 'azure-batch')
            executor_class: Executor class
            metadata: Optional metadata about the executor
        """
        if not issubclass(executor_class, CloudExecutor):
            raise ValueError(f"Executor class must inherit from CloudExecutor")
        
        if name in self._executors:
            logger.warning(f"Overriding existing executor: {name}")
        
        self._executors[name] = executor_class
        self._metadata[f"executor:{name}"] = metadata or {}
        
        logger.debug(f"Registered executor: {name} -> {executor_class}")
    
    def register_storage(
        self, 
        scheme: str, 
        storage_class: Type[CloudStorage],
        metadata: Optional[Dict[str, Any]] = None
    ) -> None:
        """
        Register a storage provider.
        
        Args:
            scheme: URI scheme (e.g., 's3', 'gs', 'az')
            storage_class: Storage class
            metadata: Optional metadata about the storage provider
        """
        if not issubclass(storage_class, CloudStorage):
            raise ValueError(f"Storage class must inherit from CloudStorage")
        
        if scheme in self._storage_providers:
            logger.warning(f"Overriding existing storage provider: {scheme}")
        
        self._storage_providers[scheme] = storage_class
        self._metadata[f"storage:{scheme}"] = metadata or {}
        
        logger.debug(f"Registered storage provider: {scheme} -> {storage_class}")
    
    def register_auth(
        self, 
        provider: str, 
        auth_class: Type[CloudAuth],
        metadata: Optional[Dict[str, Any]] = None
    ) -> None:
        """
        Register an authentication provider.
        
        Args:
            provider: Provider name (e.g., 'aws', 'azure', 'gcp')
            auth_class: Authentication class
            metadata: Optional metadata about the auth provider
        """
        if not issubclass(auth_class, CloudAuth):
            raise ValueError(f"Auth class must inherit from CloudAuth")
        
        if provider in self._auth_providers:
            logger.warning(f"Overriding existing auth provider: {provider}")
        
        self._auth_providers[provider] = auth_class
        self._metadata[f"auth:{provider}"] = metadata or {}
        
        logger.debug(f"Registered auth provider: {provider} -> {auth_class}")
    
    def get_executor(self, name: str) -> Optional[Type[CloudExecutor]]:
        """
        Get an executor class by name.
        
        Args:
            name: Executor name
            
        Returns:
            Executor class or None if not found
        """
        return self._executors.get(name)
    
    def get_storage(self, scheme: str) -> Optional[Type[CloudStorage]]:
        """
        Get a storage provider class by scheme.
        
        Args:
            scheme: URI scheme
            
        Returns:
            Storage class or None if not found
        """
        return self._storage_providers.get(scheme)
    
    def get_auth(self, provider: str) -> Optional[Type[CloudAuth]]:
        """
        Get an authentication provider class by name.
        
        Args:
            provider: Provider name
            
        Returns:
            Auth class or None if not found
        """
        return self._auth_providers.get(provider)
    
    def list_executors(self) -> List[str]:
        """List all registered executor names."""
        return list(self._executors.keys())
    
    def list_storage_schemes(self) -> List[str]:
        """List all registered storage schemes."""
        return list(self._storage_providers.keys())
    
    def list_auth_providers(self) -> List[str]:
        """List all registered auth provider names."""
        return list(self._auth_providers.keys())
    
    def get_metadata(self, component_type: str, name: str) -> Dict[str, Any]:
        """
        Get metadata for a registered component.
        
        Args:
            component_type: Type of component ('executor', 'storage', 'auth')
            name: Component name
            
        Returns:
            Metadata dictionary
        """
        key = f"{component_type}:{name}"
        return self._metadata.get(key, {})
    
    def get_all_metadata(self) -> Dict[str, Dict[str, Any]]:
        """Get all registered metadata."""
        return self._metadata.copy()
    
    def is_executor_available(self, name: str) -> bool:
        """Check if an executor is available."""
        return name in self._executors
    
    def is_storage_available(self, scheme: str) -> bool:
        """Check if a storage provider is available."""
        return scheme in self._storage_providers
    
    def is_auth_available(self, provider: str) -> bool:
        """Check if an auth provider is available."""
        return provider in self._auth_providers
    
    def auto_discover(self, package_names: Optional[List[str]] = None) -> None:
        """
        Auto-discover and register providers from specified packages.
        
        Args:
            package_names: List of package names to scan. If None, uses default packages.
        """
        if package_names is None:
            package_names = [
                'galaxy_cloud.providers.aws',
                'galaxy_cloud.providers.azure', 
                'galaxy_cloud.providers.gcp',
                'galaxy_cloud.providers.k8s',
            ]
        
        for package_name in package_names:
            try:
                self._discover_package(package_name)
            except ImportError as e:
                logger.debug(f"Could not import package {package_name}: {e}")
            except Exception as e:
                logger.warning(f"Error discovering package {package_name}: {e}")
    
    def _discover_package(self, package_name: str) -> None:
        """
        Discover and register providers from a package.
        
        Args:
            package_name: Package name to scan
        """
        try:
            package = importlib.import_module(package_name)
        except ImportError:
            logger.debug(f"Package {package_name} not available")
            return
        
        # Get all classes from the package
        for name in dir(package):
            obj = getattr(package, name)
            
            if not inspect.isclass(obj):
                continue
            
            # Check for registration decorators
            if hasattr(obj, '_registry_executor_name'):
                self.register_executor(obj._registry_executor_name, obj, 
                                     getattr(obj, '_registry_metadata', {}))
            
            if hasattr(obj, '_registry_storage_scheme'):
                self.register_storage(obj._registry_storage_scheme, obj,
                                    getattr(obj, '_registry_metadata', {}))
            
            if hasattr(obj, '_registry_auth_provider'):
                self.register_auth(obj._registry_auth_provider, obj,
                                 getattr(obj, '_registry_metadata', {}))
    
    def clear(self) -> None:
        """Clear all registered providers."""
        self._executors.clear()
        self._storage_providers.clear()
        self._auth_providers.clear()
        self._metadata.clear()
        logger.debug("Registry cleared")
    
    def status(self) -> Dict[str, Any]:
        """Get registry status."""
        return {
            "executors": len(self._executors),
            "storage_providers": len(self._storage_providers),
            "auth_providers": len(self._auth_providers),
            "executor_names": list(self._executors.keys()),
            "storage_schemes": list(self._storage_providers.keys()),
            "auth_providers": list(self._auth_providers.keys()),
        }


# Global registry instance
registry = ProviderRegistry()


# Decorator functions for easy registration

def cloud_executor(name: str, metadata: Optional[Dict[str, Any]] = None):
    """
    Decorator to register a cloud executor.
    
    Args:
        name: Executor name
        metadata: Optional metadata
        
    Example:
        @cloud_executor("aws-batch")
        class AWSBatchExecutor(CloudExecutor):
            pass
    """
    def decorator(cls: Type[CloudExecutor]) -> Type[CloudExecutor]:
        cls._registry_executor_name = name
        cls._registry_metadata = metadata or {}
        registry.register_executor(name, cls, metadata)
        return cls
    return decorator


def cloud_storage(scheme: str, metadata: Optional[Dict[str, Any]] = None):
    """
    Decorator to register a storage provider.
    
    Args:
        scheme: URI scheme
        metadata: Optional metadata
        
    Example:
        @cloud_storage("s3")
        class S3Storage(CloudStorage):
            pass
    """
    def decorator(cls: Type[CloudStorage]) -> Type[CloudStorage]:
        cls._registry_storage_scheme = scheme
        cls._registry_metadata = metadata or {}
        registry.register_storage(scheme, cls, metadata)
        return cls
    return decorator


def cloud_auth(provider: str, metadata: Optional[Dict[str, Any]] = None):
    """
    Decorator to register an authentication provider.
    
    Args:
        provider: Provider name
        metadata: Optional metadata
        
    Example:
        @cloud_auth("aws")
        class AWSAuth(CloudAuth):
            pass
    """
    def decorator(cls: Type[CloudAuth]) -> Type[CloudAuth]:
        cls._registry_auth_provider = provider
        cls._registry_metadata = metadata or {}
        registry.register_auth(provider, cls, metadata)
        return cls
    return decorator


def auto_register(func: Callable) -> Callable:
    """
    Decorator to automatically call registry.auto_discover() when the function is called.
    
    Example:
        @auto_register
        def setup():
            pass
    """
    @wraps(func)
    def wrapper(*args, **kwargs):
        if not registry._initialized:
            registry.auto_discover()
            registry._initialized = True
        return func(*args, **kwargs)
    return wrapper


# Utility functions

def get_available_providers() -> Dict[str, List[str]]:
    """
    Get all available providers by category.
    
    Returns:
        Dictionary with lists of available providers
    """
    return {
        "executors": registry.list_executors(),
        "storage": registry.list_storage_schemes(),
        "auth": registry.list_auth_providers(),
    }


def validate_provider_availability(
    executor: Optional[str] = None,
    storage: Optional[str] = None,
    auth: Optional[str] = None
) -> Dict[str, bool]:
    """
    Validate if specified providers are available.
    
    Args:
        executor: Executor name to check
        storage: Storage scheme to check
        auth: Auth provider to check
        
    Returns:
        Dictionary with availability status
    """
    result = {}
    
    if executor:
        result["executor"] = registry.is_executor_available(executor)
    
    if storage:
        result["storage"] = registry.is_storage_available(storage)
    
    if auth:
        result["auth"] = registry.is_auth_available(auth)
    
    return result


def ensure_providers_available(*provider_specs: str) -> None:
    """
    Ensure that specified providers are available, raising an error if not.
    
    Args:
        provider_specs: Provider specifications in format "type:name"
                       (e.g., "executor:aws-batch", "storage:s3")
                       
    Raises:
        ValueError: If any provider is not available
    """
    missing = []
    
    for spec in provider_specs:
        if ":" not in spec:
            raise ValueError(f"Invalid provider spec: {spec}. Use 'type:name' format.")
        
        provider_type, name = spec.split(":", 1)
        
        if provider_type == "executor" and not registry.is_executor_available(name):
            missing.append(spec)
        elif provider_type == "storage" and not registry.is_storage_available(name):
            missing.append(spec)
        elif provider_type == "auth" and not registry.is_auth_available(name):
            missing.append(spec)
        elif provider_type not in ("executor", "storage", "auth"):
            raise ValueError(f"Unknown provider type: {provider_type}")
    
    if missing:
        raise ValueError(f"Required providers not available: {', '.join(missing)}")