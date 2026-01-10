"""
Google Cloud Platform authentication provider implementation.
"""

import os
import json
from typing import Dict, Any, Optional, List
from datetime import datetime, timedelta

from google.auth import default, exceptions as auth_exceptions
from google.auth.credentials import Credentials
from google.oauth2 import service_account
from google.oauth2.credentials import UserAccessTokenCredentials
from google.auth.transport.requests import Request
from google.cloud import iam_credentials_v1

from galaxy_cloud.core.auth import CloudAuth, CloudCredentials
from galaxy_cloud.registry import cloud_auth


@cloud_auth("gcp", {
    "description": "Google Cloud Platform authentication provider",
    "supported_methods": [
        "service_account", "application_default", "user_credentials", 
        "impersonation", "metadata_service", "external_account"
    ],
    "version": "1.0.0"
})
class GCPAuth(CloudAuth):
    """Google Cloud Platform authentication provider."""
    
    def __init__(self, config: Dict[str, Any], **kwargs):
        super().__init__(config, **kwargs)
        
        # GCP authentication configuration
        self.project_id = config.get('project_id') or os.getenv('GOOGLE_CLOUD_PROJECT')
        self.service_account_path = config.get('service_account_path') or os.getenv('GOOGLE_APPLICATION_CREDENTIALS')
        self.service_account_email = config.get('service_account_email')
        self.service_account_key = config.get('service_account_key')  # JSON key as string
        
        # Authentication method
        self.auth_method = config.get('auth_method', 'application_default')
        
        # Scopes for different GCP services
        self.default_scopes = config.get('scopes', [
            'https://www.googleapis.com/auth/cloud-platform'
        ])
        
        # Service account impersonation
        self.impersonate_service_account = config.get('impersonate_service_account')
        self.impersonation_chain = config.get('impersonation_chain', [])
        self.delegate_scopes = config.get('delegate_scopes', [])
        
        # User credentials configuration
        self.client_id = config.get('client_id')
        self.client_secret = config.get('client_secret')
        self.refresh_token = config.get('refresh_token')
        
        # Token caching
        self.enable_credential_cache = config.get('enable_credential_cache', True)
        self.cache_timeout_minutes = config.get('cache_timeout_minutes', 55)  # Refresh before 60min expiry
        
        # Quota project for billing
        self.quota_project_id = config.get('quota_project_id')
        
        # Internal state
        self.credentials: Optional[Credentials] = None
        self.cached_tokens: Dict[str, tuple[str, datetime]] = {}
        
    async def initialize(self) -> None:
        """Initialize GCP authentication."""
        try:
            self.credentials = await self._create_credentials()
            
            # Test the credentials
            await self._test_credentials()
            
            self._initialized = True
            self.logger.info(f"GCP authentication initialized using method: {self.auth_method}")
            
        except Exception as e:
            self.logger.error(f"Failed to initialize GCP authentication: {e}")
            raise
    
    async def cleanup(self) -> None:
        """Clean up GCP authentication resources."""
        if self.credentials:
            # Some credentials may have cleanup methods
            if hasattr(self.credentials, 'close'):
                await self.credentials.close()
            self.credentials = None
        
        self.cached_tokens.clear()
        self._initialized = False
        self.logger.info("GCP authentication cleaned up")
    
    @property
    def provider_name(self) -> str:
        return "gcp"
    
    async def get_credentials(self, force_refresh: bool = False) -> CloudCredentials:
        """Get GCP credentials."""
        if not self._initialized:
            raise RuntimeError("Authentication provider not initialized")
        
        try:
            # Refresh credentials if needed
            if force_refresh or self._needs_refresh():
                await self._refresh_credentials()
            
            # Get access token
            token = await self._get_access_token(self.default_scopes, force_refresh)
            
            # Create credentials object
            credentials_data = {
                'access_token': token,
                'token_type': 'Bearer',
                'project_id': self.project_id,
                'auth_method': self.auth_method,
                'service_account_email': self.service_account_email,
                'impersonate_service_account': self.impersonate_service_account
            }
            
            return CloudCredentials(
                credentials_data,
                raw_credentials=self.credentials
            )
            
        except Exception as e:
            self.logger.error(f"Failed to get GCP credentials: {e}")
            raise
    
    async def refresh_credentials(self) -> CloudCredentials:
        """Refresh GCP credentials."""
        return await self.get_credentials(force_refresh=True)
    
    async def get_access_token(self, scopes: List[str] = None, force_refresh: bool = False) -> str:
        """Get access token for specific scopes."""
        scopes = scopes or self.default_scopes
        return await self._get_access_token(scopes, force_refresh)
    
    async def get_service_account_token(self, target_audience: str = None, include_email: bool = False) -> str:
        """Get ID token for service account."""
        try:
            if not self.service_account_email:
                raise ValueError("Service account email required for ID token")
            
            # Use IAM Service Account Credentials API
            client = iam_credentials_v1.IAMCredentialsAsyncClient(credentials=self.credentials)
            
            request = iam_credentials_v1.GenerateIdTokenRequest(
                name=f"projects/-/serviceAccounts/{self.service_account_email}",
                audience=target_audience or self.project_id,
                include_email=include_email
            )
            
            response = await client.generate_id_token(request=request)
            return response.token
            
        except Exception as e:
            self.logger.error(f"Failed to get service account token: {e}")
            raise
    
    async def impersonate_service_account(self, target_service_account: str, scopes: List[str] = None) -> CloudCredentials:
        """Impersonate a service account."""
        try:
            from google.auth import impersonated_credentials
            
            scopes = scopes or self.default_scopes
            
            # Create impersonated credentials
            impersonated_creds = impersonated_credentials.Credentials(
                source_credentials=self.credentials,
                target_principal=target_service_account,
                target_scopes=scopes,
                quota_project_id=self.quota_project_id
            )
            
            # Refresh to get token
            request = Request()
            impersonated_creds.refresh(request)
            
            credentials_data = {
                'access_token': impersonated_creds.token,
                'token_type': 'Bearer',
                'project_id': self.project_id,
                'auth_method': 'impersonated',
                'service_account_email': target_service_account,
                'impersonate_service_account': target_service_account
            }
            
            return CloudCredentials(
                credentials_data,
                raw_credentials=impersonated_creds
            )
            
        except Exception as e:
            self.logger.error(f"Failed to impersonate service account {target_service_account}: {e}")
            raise
    
    # Private methods
    
    async def _create_credentials(self) -> Credentials:
        """Create GCP credentials based on configuration."""
        if self.auth_method == 'service_account':
            if self.service_account_key:
                # Use service account key from string
                key_data = json.loads(self.service_account_key)
                return service_account.Credentials.from_service_account_info(
                    key_data,
                    scopes=self.default_scopes,
                    quota_project_id=self.quota_project_id
                )
            elif self.service_account_path:
                # Use service account key from file
                return service_account.Credentials.from_service_account_file(
                    self.service_account_path,
                    scopes=self.default_scopes,
                    quota_project_id=self.quota_project_id
                )
            else:
                raise ValueError("Service account authentication requires either service_account_key or service_account_path")
        
        elif self.auth_method == 'user_credentials':
            if not all([self.client_id, self.client_secret, self.refresh_token]):
                raise ValueError("User credentials authentication requires client_id, client_secret, and refresh_token")
            
            from google.oauth2.credentials import UserAccessTokenCredentials
            
            return UserAccessTokenCredentials(
                token=None,  # Will be refreshed
                refresh_token=self.refresh_token,
                client_id=self.client_id,
                client_secret=self.client_secret,
                token_uri='https://oauth2.googleapis.com/token',
                scopes=self.default_scopes,
                quota_project_id=self.quota_project_id
            )
        
        elif self.auth_method == 'impersonation':
            if not self.impersonate_service_account:
                raise ValueError("Impersonation authentication requires impersonate_service_account")
            
            # First get source credentials
            source_credentials, _ = default(
                scopes=self.default_scopes,
                quota_project_id=self.quota_project_id
            )
            
            from google.auth import impersonated_credentials
            
            return impersonated_credentials.Credentials(
                source_credentials=source_credentials,
                target_principal=self.impersonate_service_account,
                target_scopes=self.default_scopes,
                quota_project_id=self.quota_project_id
            )
        
        elif self.auth_method == 'application_default':
            # Use Application Default Credentials (ADC)
            credentials, project_id = default(
                scopes=self.default_scopes,
                quota_project_id=self.quota_project_id
            )
            
            # Set project_id if not configured
            if not self.project_id and project_id:
                self.project_id = project_id
            
            return credentials
        
        else:
            raise ValueError(f"Unsupported authentication method: {self.auth_method}")
    
    async def _test_credentials(self) -> None:
        """Test the credentials by making a simple API call."""
        try:
            # Refresh credentials to get a token
            request = Request()
            self.credentials.refresh(request)
            
            if not self.credentials.token:
                raise auth_exceptions.RefreshError("Failed to obtain access token")
            
            self.logger.debug("GCP credential test successful")
            
        except Exception as e:
            self.logger.error(f"GCP credential test failed: {e}")
            raise auth_exceptions.RefreshError(f"GCP authentication test failed: {e}")
    
    def _needs_refresh(self) -> bool:
        """Check if credentials need refresh."""
        if not self.credentials:
            return True
        
        if not hasattr(self.credentials, 'expiry') or not self.credentials.expiry:
            return False
        
        # Refresh if expiring within 5 minutes
        buffer_time = timedelta(minutes=5)
        return datetime.utcnow() + buffer_time >= self.credentials.expiry
    
    async def _refresh_credentials(self) -> None:
        """Refresh the credentials."""
        try:
            request = Request()
            self.credentials.refresh(request)
            
            self.logger.debug("Refreshed GCP credentials")
            
        except Exception as e:
            self.logger.error(f"Failed to refresh GCP credentials: {e}")
            raise
    
    async def _get_access_token(self, scopes: List[str], force_refresh: bool = False) -> str:
        """Get access token with caching."""
        scope_key = '|'.join(sorted(scopes))
        
        # Check cache
        if not force_refresh and self.enable_credential_cache:
            if scope_key in self.cached_tokens:
                token, cached_at = self.cached_tokens[scope_key]
                
                # Check if token is still valid (with buffer time)
                if datetime.now() + timedelta(minutes=5) < cached_at + timedelta(minutes=self.cache_timeout_minutes):
                    self.logger.debug(f"Using cached token for scopes: {scopes}")
                    return token
                else:
                    # Remove expired token from cache
                    del self.cached_tokens[scope_key]
        
        # Get new token
        try:
            # If scopes differ from configured scopes, create new credentials
            if set(scopes) != set(self.default_scopes):
                if hasattr(self.credentials, 'with_scopes'):
                    scoped_credentials = self.credentials.with_scopes(scopes)
                else:
                    scoped_credentials = self.credentials
            else:
                scoped_credentials = self.credentials
            
            # Refresh if needed
            if self._needs_refresh() or force_refresh:
                request = Request()
                scoped_credentials.refresh(request)
            
            token = scoped_credentials.token
            
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
        info = {
            'auth_method': self.auth_method,
            'project_id': self.project_id,
            'service_account_email': self.service_account_email,
            'impersonate_service_account': self.impersonate_service_account,
            'has_service_account_key': bool(self.service_account_key or self.service_account_path),
            'quota_project_id': self.quota_project_id,
            'cached_tokens_count': len(self.cached_tokens),
            'default_scopes': self.default_scopes
        }
        
        if self.credentials:
            info.update({
                'has_token': bool(self.credentials.token),
                'token_expires': self.credentials.expiry.isoformat() if hasattr(self.credentials, 'expiry') and self.credentials.expiry else None,
                'is_expired': self.credentials.expired if hasattr(self.credentials, 'expired') else None
            })
        
        return info
    
    async def validate_permissions(self, resource: str = None) -> Dict[str, bool]:
        """Validate permissions for common operations."""
        try:
            from google.cloud import resource_manager
            
            permissions = {
                'read_project': False,
                'create_resources': False,
                'manage_iam': False,
                'use_service_accounts': False
            }
            
            try:
                # Test basic project access
                client = resource_manager.Client(credentials=self.credentials, project=self.project_id)
                project = client.fetch_project(self.project_id)
                if project:
                    permissions['read_project'] = True
                    
            except Exception as e:
                self.logger.warning(f"Failed to validate project permissions: {e}")
            
            # Add more specific permission checks as needed
            
            return permissions
            
        except Exception as e:
            self.logger.error(f"Failed to validate permissions: {e}")
            return {}
    
    async def get_project_info(self) -> Dict[str, Any]:
        """Get information about the current project."""
        try:
            from google.cloud import resource_manager
            
            client = resource_manager.Client(credentials=self.credentials, project=self.project_id)
            project = client.fetch_project(self.project_id)
            
            if project:
                return {
                    'project_id': project.project_id,
                    'name': project.name,
                    'number': project.number,
                    'lifecycle_state': project.lifecycle_state,
                    'create_time': project.create_time,
                    'labels': project.labels
                }
            else:
                return {'error': 'Project not found or no access'}
                
        except Exception as e:
            self.logger.error(f"Failed to get project info: {e}")
            return {'error': str(e)}
    
    async def list_service_accounts(self) -> List[Dict[str, Any]]:
        """List service accounts in the project."""
        try:
            from google.cloud import iam_admin_v1
            
            client = iam_admin_v1.IAMAsyncClient(credentials=self.credentials)
            
            project_path = f"projects/{self.project_id}"
            request = iam_admin_v1.ListServiceAccountsRequest(name=project_path)
            
            response = await client.list_service_accounts(request=request)
            
            service_accounts = []
            for account in response.accounts:
                service_accounts.append({
                    'name': account.name,
                    'email': account.email,
                    'display_name': account.display_name,
                    'description': account.description,
                    'unique_id': account.unique_id,
                    'disabled': account.disabled
                })
            
            return service_accounts
            
        except Exception as e:
            self.logger.error(f"Failed to list service accounts: {e}")
            return []
    
    def clear_token_cache(self) -> None:
        """Clear the token cache."""
        self.cached_tokens.clear()
        self.logger.info("GCP token cache cleared")
    
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
            
            # Create new credentials
            self.credentials = await self._create_credentials()
            
            # Test new credentials
            await self._test_credentials()
            
            self.logger.info(f"Rotated GCP credentials from {old_auth_method} to {self.auth_method}")
            
        except Exception as e:
            self.logger.error(f"Failed to rotate credentials: {e}")
            raise
    
    async def create_signed_jwt(self, audience: str, expiry_minutes: int = 60) -> str:
        """Create a signed JWT token."""
        try:
            if self.auth_method != 'service_account':
                raise ValueError("Signed JWT creation requires service account credentials")
            
            import jwt
            from datetime import datetime, timezone
            
            now = datetime.now(timezone.utc)
            payload = {
                'iss': self.service_account_email,
                'sub': self.service_account_email,
                'aud': audience,
                'iat': now,
                'exp': now + timedelta(minutes=expiry_minutes)
            }
            
            # Get private key from service account credentials
            if hasattr(self.credentials, '_private_key'):
                private_key = self.credentials._private_key
            else:
                raise ValueError("Unable to access private key from credentials")
            
            # Create JWT
            token = jwt.encode(payload, private_key, algorithm='RS256')
            
            return token
            
        except Exception as e:
            self.logger.error(f"Failed to create signed JWT: {e}")
            raise