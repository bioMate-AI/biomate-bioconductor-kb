"""
Cloud authentication abstraction layer.
"""

from abc import ABC, abstractmethod
from typing import Dict, Any, Optional
from datetime import datetime, timedelta


class CloudCredentials:
    """Container for cloud credentials."""
    
    def __init__(self, credentials: Dict[str, Any], expires_at: Optional[datetime] = None):
        """
        Initialize credentials.
        
        Args:
            credentials: Credential data
            expires_at: Optional expiration time
        """
        self.credentials = credentials
        self.expires_at = expires_at
        self.created_at = datetime.utcnow()
    
    @property
    def is_expired(self) -> bool:
        """Check if credentials are expired."""
        if self.expires_at is None:
            return False
        return datetime.utcnow() >= self.expires_at
    
    @property
    def expires_in_seconds(self) -> Optional[int]:
        """Get seconds until expiration."""
        if self.expires_at is None:
            return None
        delta = self.expires_at - datetime.utcnow()
        return max(0, int(delta.total_seconds()))
    
    def get(self, key: str, default: Any = None) -> Any:
        """Get a credential value."""
        return self.credentials.get(key, default)
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return self.credentials.copy()


class CloudAuth(ABC):
    """
    Abstract base class for cloud authentication.
    """
    
    def __init__(self, config: Dict[str, Any]):
        """
        Initialize authentication.
        
        Args:
            config: Authentication configuration
        """
        self.config = config
        self._credentials: Optional[CloudCredentials] = None
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
        """Initialize authentication."""
        pass
    
    @abstractmethod
    async def cleanup(self) -> None:
        """Clean up authentication resources."""
        pass
    
    @property
    @abstractmethod
    def provider_name(self) -> str:
        """Return the authentication provider name."""
        pass
    
    @abstractmethod
    async def get_credentials(self, force_refresh: bool = False) -> CloudCredentials:
        """
        Get current credentials, refreshing if necessary.
        
        Args:
            force_refresh: Force credential refresh
            
        Returns:
            Current credentials
        """
        pass
    
    @abstractmethod
    async def refresh_credentials(self) -> CloudCredentials:
        """
        Refresh credentials.
        
        Returns:
            New credentials
        """
        pass
    
    async def ensure_valid_credentials(self) -> CloudCredentials:
        """
        Ensure credentials are valid, refreshing if necessary.
        
        Returns:
            Valid credentials
        """
        if self._credentials is None or self._credentials.is_expired:
            self._credentials = await self.refresh_credentials()
        return self._credentials
    
    async def is_authenticated(self) -> bool:
        """
        Check if authentication is valid.
        
        Returns:
            True if authenticated, False otherwise
        """
        try:
            await self.ensure_valid_credentials()
            return True
        except Exception:
            return False
    
    def get_auth_headers(self) -> Dict[str, str]:
        """
        Get authentication headers for HTTP requests.
        
        Returns:
            Dictionary of headers
        """
        return {}
    
    async def test_connection(self) -> Dict[str, Any]:
        """
        Test the authentication by making a simple API call.
        
        Returns:
            Test result with status and details
        """
        try:
            credentials = await self.ensure_valid_credentials()
            return {
                "status": "success",
                "provider": self.provider_name,
                "authenticated": True,
                "expires_in": credentials.expires_in_seconds,
            }
        except Exception as e:
            return {
                "status": "failed",
                "provider": self.provider_name,
                "authenticated": False,
                "error": str(e),
            }


class StaticAuth(CloudAuth):
    """Authentication using static credentials."""
    
    def __init__(self, config: Dict[str, Any], provider_name: str = "static"):
        """
        Initialize static authentication.
        
        Args:
            config: Static credentials configuration
            provider_name: Provider name for identification
        """
        super().__init__(config)
        self._provider_name = provider_name
    
    async def initialize(self) -> None:
        """Initialize static authentication."""
        self._initialized = True
        # Create static credentials that don't expire
        self._credentials = CloudCredentials(self.config.copy())
    
    async def cleanup(self) -> None:
        """Clean up static authentication."""
        self._credentials = None
        self._initialized = False
    
    @property
    def provider_name(self) -> str:
        """Return the provider name."""
        return self._provider_name
    
    async def get_credentials(self, force_refresh: bool = False) -> CloudCredentials:
        """Get static credentials."""
        if self._credentials is None:
            await self.initialize()
        return self._credentials
    
    async def refresh_credentials(self) -> CloudCredentials:
        """Refresh static credentials (no-op)."""
        return await self.get_credentials()


class NoAuth(CloudAuth):
    """No authentication (for anonymous access)."""
    
    def __init__(self, provider_name: str = "none"):
        """
        Initialize no authentication.
        
        Args:
            provider_name: Provider name for identification
        """
        super().__init__({})
        self._provider_name = provider_name
    
    async def initialize(self) -> None:
        """Initialize no authentication."""
        self._initialized = True
        self._credentials = CloudCredentials({})
    
    async def cleanup(self) -> None:
        """Clean up no authentication."""
        self._credentials = None
        self._initialized = False
    
    @property
    def provider_name(self) -> str:
        """Return the provider name."""
        return self._provider_name
    
    async def get_credentials(self, force_refresh: bool = False) -> CloudCredentials:
        """Get empty credentials."""
        if self._credentials is None:
            await self.initialize()
        return self._credentials
    
    async def refresh_credentials(self) -> CloudCredentials:
        """Refresh empty credentials (no-op)."""
        return await self.get_credentials()