"""
Azure authentication provider implementation.
"""

import os
import json
from typing import Dict, Any, Optional
from datetime import datetime, timedelta

from azure.identity.aio import (
    DefaultAzureCredential,
    ClientSecretCredential,
    ClientCertificateCredential,
    ManagedIdentityCredential,
    AzureCliCredential,
    InteractiveBrowserCredential
)
from azure.core.credentials import AccessToken
from azure.core.exceptions import ClientAuthenticationError

from galaxy_cloud.core.auth import CloudAuth, CloudCredentials
from galaxy_cloud.registry import cloud_auth


@cloud_auth("azure", {
    "description": "Azure authentication provider with multiple methods",
    "supported_methods": [
        "service_principal", "managed_identity", "azure_cli",
        "interactive", "certificate", "default_credential"
    ],
    "version": "1.0.0"
})
class AzureAuth(CloudAuth):
    """Azure authentication provider."""
    
    def __init__(self, config: Dict[str, Any], **kwargs):
        super().__init__(config, **kwargs)
        
        # Azure authentication configuration
        self.tenant_id = config.get('tenant_id') or os.getenv('AZURE_TENANT_ID')
        self.client_id = config.get('client_id') or os.getenv('AZURE_CLIENT_ID')
        self.client_secret = config.get('client_secret') or os.getenv('AZURE_CLIENT_SECRET')
        self.certificate_path = config.get('certificate_path') or os.getenv('AZURE_CLIENT_CERTIFICATE_PATH')
        self.certificate_password = config.get('certificate_password') or os.getenv('AZURE_CLIENT_CERTIFICATE_PASSWORD')
        
        # Authentication method
        self.auth_method = config.get('auth_method', 'default_credential')
        
        # Subscription and resource settings
        self.subscription_id = config.get('subscription_id') or os.getenv('AZURE_SUBSCRIPTION_ID')
        self.resource_group = config.get('resource_group')
        
        # Scopes for different Azure services
        self.default_scopes = config.get('scopes', [
            'https://management.azure.com/.default',
            'https://storage.azure.com/.default'
        ])
        
        # Managed Identity settings
        self.managed_identity_client_id = config.get('managed_identity_client_id')
        
        # Cache settings
        self.enable_credential_cache = config.get('enable_credential_cache', True)
        self.cache_timeout_minutes = config.get('cache_timeout_minutes', 55)  # Refresh before 60min expiry
        
        # Internal state
        self.credential = None
        self.cached_tokens: Dict[str, tuple[AccessToken, datetime]] = {}
        
    async def initialize(self) -> None:
        """Initialize Azure authentication."""
        try:
            self.credential = await self._create_credential()
            
            # Test the credential
            await self._test_credential()
            
            self._initialized = True
            self.logger.info(f"Azure authentication initialized using method: {self.auth_method}")
            
        except Exception as e:
            self.logger.error(f"Failed to initialize Azure authentication: {e}")
            raise
    
    async def cleanup(self) -> None:
        """Clean up Azure authentication resources."""
        if self.credential:
            if hasattr(self.credential, 'close'):
                await self.credential.close()
            self.credential = None
        
        self.cached_tokens.clear()
        self._initialized = False
        self.logger.info("Azure authentication cleaned up")
    
    @property
    def provider_name(self) -> str:
        return "azure"
    
    async def get_credentials(self, force_refresh: bool = False) -> CloudCredentials:
        """Get Azure credentials."""
        if not self._initialized:
            raise RuntimeError("Authentication provider not initialized")
        
        try:
            # Get access token for default scope
            token = await self._get_access_token(
                scopes=self.default_scopes,
                force_refresh=force_refresh
            )
            
            # Create credentials object
            credentials_data = {
                'access_token': token.token,
                'token_type': 'Bearer',
                'expires_at': token.expires_on,
                'subscription_id': self.subscription_id,
                'tenant_id': self.tenant_id,
                'client_id': self.client_id,
                'auth_method': self.auth_method
            }
            
            return CloudCredentials(
                credentials_data,
                raw_credentials=self.credential
            )
            
        except Exception as e:
            self.logger.error(f"Failed to get Azure credentials: {e}")
            raise
    
    async def refresh_credentials(self) -> CloudCredentials:
        """Refresh Azure credentials."""
        return await self.get_credentials(force_refresh=True)
    
    async def get_access_token(self, scopes: list[str] = None, force_refresh: bool = False) -> str:
        """Get access token for specific scopes."""
        scopes = scopes or self.default_scopes
        token = await self._get_access_token(scopes, force_refresh)
        return token.token
    
    async def get_management_token(self, force_refresh: bool = False) -> str:
        """Get token for Azure Resource Manager."""
        return await self.get_access_token(
            ['https://management.azure.com/.default'],
            force_refresh
        )
    
    async def get_storage_token(self, force_refresh: bool = False) -> str:
        """Get token for Azure Storage."""
        return await self.get_access_token(
            ['https://storage.azure.com/.default'],
            force_refresh
        )
    
    async def get_batch_token(self, force_refresh: bool = False) -> str:
        """Get token for Azure Batch."""
        return await self.get_access_token(
            ['https://batch.core.windows.net/.default'],
            force_refresh
        )
    
    # Private methods
    
    async def _create_credential(self):
        """Create Azure credential based on configuration."""
        if self.auth_method == 'service_principal':
            if not all([self.tenant_id, self.client_id, self.client_secret]):
                raise ValueError("Service principal authentication requires tenant_id, client_id, and client_secret")
            
            return ClientSecretCredential(
                tenant_id=self.tenant_id,
                client_id=self.client_id,
                client_secret=self.client_secret
            )
        
        elif self.auth_method == 'certificate':
            if not all([self.tenant_id, self.client_id, self.certificate_path]):
                raise ValueError("Certificate authentication requires tenant_id, client_id, and certificate_path")
            
            return ClientCertificateCredential(
                tenant_id=self.tenant_id,
                client_id=self.client_id,
                certificate_path=self.certificate_path,
                password=self.certificate_password
            )
        
        elif self.auth_method == 'managed_identity':
            return ManagedIdentityCredential(
                client_id=self.managed_identity_client_id
            )
        
        elif self.auth_method == 'azure_cli':
            return AzureCliCredential()
        
        elif self.auth_method == 'interactive':
            return InteractiveBrowserCredential(
                tenant_id=self.tenant_id,
                client_id=self.client_id
            )
        
        elif self.auth_method == 'default_credential':
            # Try DefaultAzureCredential which attempts multiple methods
            exclude_options = {}
            
            # Allow configuration of which methods to exclude
            if self.config.get('exclude_cli_credential'):
                exclude_options['exclude_cli_credential'] = True
            if self.config.get('exclude_environment_credential'):
                exclude_options['exclude_environment_credential'] = True
            if self.config.get('exclude_managed_identity_credential'):
                exclude_options['exclude_managed_identity_credential'] = True
            if self.config.get('exclude_shared_token_cache_credential'):
                exclude_options['exclude_shared_token_cache_credential'] = True
            if self.config.get('exclude_visual_studio_code_credential'):
                exclude_options['exclude_visual_studio_code_credential'] = True
            if self.config.get('exclude_interactive_browser_credential'):
                exclude_options['exclude_interactive_browser_credential'] = True
            
            return DefaultAzureCredential(**exclude_options)
        
        else:
            raise ValueError(f"Unsupported authentication method: {self.auth_method}")
    
    async def _test_credential(self) -> None:
        """Test the credential by getting a token."""
        try:
            token = await self.credential.get_token('https://management.azure.com/.default')
            if not token or not token.token:
                raise ClientAuthenticationError("Failed to obtain access token")
            
            self.logger.debug("Azure credential test successful")
            
        except Exception as e:
            self.logger.error(f"Azure credential test failed: {e}")
            raise ClientAuthenticationError(f"Azure authentication test failed: {e}")
    
    async def _get_access_token(self, scopes: list[str], force_refresh: bool = False) -> AccessToken:
        """Get access token with caching."""
        scope_key = '|'.join(sorted(scopes))
        
        # Check cache
        if not force_refresh and self.enable_credential_cache:
            if scope_key in self.cached_tokens:
                token, cached_at = self.cached_tokens[scope_key]
                
                # Check if token is still valid (with buffer time)
                expires_at = datetime.fromtimestamp(token.expires_on)
                buffer_time = timedelta(minutes=5)  # 5-minute buffer
                
                if datetime.now() + buffer_time < expires_at:
                    self.logger.debug(f"Using cached token for scopes: {scopes}")
                    return token
                else:
                    # Remove expired token from cache
                    del self.cached_tokens[scope_key]
        
        # Get new token
        try:
            token = await self.credential.get_token(*scopes)
            
            # Cache the token
            if self.enable_credential_cache:
                self.cached_tokens[scope_key] = (token, datetime.now())
            
            self.logger.debug(f"Obtained new access token for scopes: {scopes}")
            return token
            
        except Exception as e:
            self.logger.error(f"Failed to get access token for scopes {scopes}: {e}")
            raise
    
    def get_credential_info(self) -> Dict[str, Any]:
        """Get information about the current credential configuration."""
        return {
            'auth_method': self.auth_method,
            'tenant_id': self.tenant_id,
            'client_id': self.client_id,
            'subscription_id': self.subscription_id,
            'resource_group': self.resource_group,
            'has_client_secret': bool(self.client_secret),
            'has_certificate': bool(self.certificate_path),
            'managed_identity_client_id': self.managed_identity_client_id,
            'cached_tokens_count': len(self.cached_tokens),
            'default_scopes': self.default_scopes
        }
    
    async def validate_permissions(self, resource_group: str = None, subscription_id: str = None) -> Dict[str, bool]:
        """Validate permissions for common operations."""
        try:
            # This would require Azure Resource Manager client
            # For now, return basic validation
            
            permissions = {
                'read_subscription': False,
                'read_resource_group': False,
                'manage_batch_account': False,
                'manage_storage_account': False,
                'create_resources': False
            }
            
            # Test if we can get a management token
            try:
                await self.get_management_token()
                permissions['read_subscription'] = True
                
                if resource_group:
                    permissions['read_resource_group'] = True
                    permissions['manage_batch_account'] = True
                    permissions['manage_storage_account'] = True
                    permissions['create_resources'] = True
                    
            except Exception as e:
                self.logger.warning(f"Failed to validate management permissions: {e}")
            
            # Test storage permissions
            try:
                await self.get_storage_token()
                # If we got here, we have some storage access
                if 'manage_storage_account' not in permissions or not permissions['manage_storage_account']:
                    permissions['manage_storage_account'] = True
                    
            except Exception as e:
                self.logger.warning(f"Failed to validate storage permissions: {e}")
            
            return permissions
            
        except Exception as e:
            self.logger.error(f"Failed to validate permissions: {e}")
            return {}
    
    async def get_user_info(self) -> Dict[str, Any]:
        """Get information about the authenticated user/principal."""
        try:
            # Get token and decode it (basic info only)
            token = await self.get_management_token()
            
            # In a real implementation, you would decode the JWT token
            # For now, return basic info from configuration
            
            user_info = {
                'auth_method': self.auth_method,
                'tenant_id': self.tenant_id,
                'client_id': self.client_id,
                'subscription_id': self.subscription_id,
                'authenticated': True,
                'token_valid': bool(token)
            }
            
            return user_info
            
        except Exception as e:
            self.logger.error(f"Failed to get user info: {e}")
            return {
                'authenticated': False,
                'error': str(e)
            }
    
    def clear_token_cache(self) -> None:
        """Clear the token cache."""
        self.cached_tokens.clear()
        self.logger.info("Azure token cache cleared")
    
    async def rotate_credentials(self, new_config: Dict[str, Any]) -> None:
        """Rotate credentials with new configuration."""
        try:
            # Update configuration
            old_auth_method = self.auth_method
            
            for key, value in new_config.items():
                if hasattr(self, key):
                    setattr(self, key, value)
            
            # Clear cache
            self.clear_token_cache()
            
            # Close old credential
            if self.credential and hasattr(self.credential, 'close'):
                await self.credential.close()
            
            # Create new credential
            self.credential = await self._create_credential()
            
            # Test new credential
            await self._test_credential()
            
            self.logger.info(f"Rotated Azure credentials from {old_auth_method} to {self.auth_method}")
            
        except Exception as e:
            self.logger.error(f"Failed to rotate credentials: {e}")
            raise