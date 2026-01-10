"""
AWS authentication implementation.
"""

import asyncio
import logging
from typing import Dict, Any, Optional
from datetime import datetime, timedelta

try:
    import boto3
    from botocore.exceptions import ClientError, NoCredentialsError
    BOTO3_AVAILABLE = True
except ImportError:
    BOTO3_AVAILABLE = False

from ...core.auth import CloudAuth, CloudCredentials
from ...registry import cloud_auth

logger = logging.getLogger(__name__)


@cloud_auth("aws", metadata={"requires": ["boto3"], "description": "AWS authentication using boto3"})
class AWSAuth(CloudAuth):
    """
    AWS authentication implementation using boto3.
    
    Supports multiple authentication methods:
    - Static access keys
    - IAM roles
    - AWS profiles
    - Instance metadata service
    """
    
    def __init__(self, config: Dict[str, Any]):
        """
        Initialize AWS authentication.
        
        Args:
            config: AWS authentication configuration
        """
        super().__init__(config)
        
        if not BOTO3_AVAILABLE:
            raise ImportError("boto3 is required for AWS authentication. Install with: pip install boto3")
        
        self._session: Optional[boto3.Session] = None
        self._sts_client = None
        
    async def initialize(self) -> None:
        """Initialize AWS authentication."""
        self._session = self._create_session()
        self._sts_client = self._session.client('sts')
        self._initialized = True
        
        # Get initial credentials
        await self.get_credentials()
    
    async def cleanup(self) -> None:
        """Clean up AWS authentication."""
        self._session = None
        self._sts_client = None
        self._credentials = None
        self._initialized = False
    
    @property
    def provider_name(self) -> str:
        """Return the provider name."""
        return "aws"
    
    def _create_session(self) -> boto3.Session:
        """Create a boto3 session based on configuration."""
        session_kwargs = {}
        
        # Static credentials
        if self.config.get('access_key_id') and self.config.get('secret_access_key'):
            session_kwargs.update({
                'aws_access_key_id': self.config['access_key_id'],
                'aws_secret_access_key': self.config['secret_access_key'],
                'aws_session_token': self.config.get('session_token'),
            })
        
        # Profile-based authentication
        if self.config.get('profile'):
            session_kwargs['profile_name'] = self.config['profile']
        
        # Region
        if self.config.get('region'):
            session_kwargs['region_name'] = self.config['region']
        
        return boto3.Session(**session_kwargs)
    
    async def get_credentials(self, force_refresh: bool = False) -> CloudCredentials:
        """
        Get current AWS credentials.
        
        Args:
            force_refresh: Force credential refresh
            
        Returns:
            Current credentials
        """
        if force_refresh or self._credentials is None or self._credentials.is_expired:
            self._credentials = await self.refresh_credentials()
        
        return self._credentials
    
    async def refresh_credentials(self) -> CloudCredentials:
        """
        Refresh AWS credentials.
        
        Returns:
            New credentials
        """
        try:
            # Check if we need to assume a role
            if self.config.get('role_arn'):
                return await self._assume_role()
            else:
                return await self._get_session_credentials()
        except Exception as e:
            logger.error(f"Failed to refresh AWS credentials: {e}")
            raise
    
    async def _get_session_credentials(self) -> CloudCredentials:
        """Get credentials from the current session."""
        def _get_creds():
            # Get credentials from session
            creds = self._session.get_credentials()
            if creds is None:
                raise NoCredentialsError("No AWS credentials found")
            
            return {
                'access_key_id': creds.access_key,
                'secret_access_key': creds.secret_key,
                'session_token': creds.token,
                'region': self._session.region_name,
            }
        
        # Run in thread pool to avoid blocking
        loop = asyncio.get_event_loop()
        creds_dict = await loop.run_in_executor(None, _get_creds)
        
        # Credentials from session don't have explicit expiration
        # Set a reasonable refresh time
        expires_at = datetime.utcnow() + timedelta(hours=1)
        
        return CloudCredentials(creds_dict, expires_at)
    
    async def _assume_role(self) -> CloudCredentials:
        """Assume an IAM role and get temporary credentials."""
        def _assume():
            role_arn = self.config['role_arn']
            session_name = self.config.get('role_session_name', 'galaxy-cloud-executor')
            duration = self.config.get('role_duration_seconds', 3600)
            
            response = self._sts_client.assume_role(
                RoleArn=role_arn,
                RoleSessionName=session_name,
                DurationSeconds=duration
            )
            
            creds = response['Credentials']
            return {
                'access_key_id': creds['AccessKeyId'],
                'secret_access_key': creds['SecretAccessKey'], 
                'session_token': creds['SessionToken'],
                'region': self._session.region_name,
            }, creds['Expiration']
        
        # Run in thread pool
        loop = asyncio.get_event_loop()
        creds_dict, expiration = await loop.run_in_executor(None, _assume)
        
        return CloudCredentials(creds_dict, expiration)
    
    def get_auth_headers(self) -> Dict[str, str]:
        """
        Get authentication headers for HTTP requests.
        
        Note: AWS uses signature-based authentication, not headers.
        This method returns empty dict.
        """
        return {}
    
    async def test_connection(self) -> Dict[str, Any]:
        """
        Test the AWS authentication by calling STS GetCallerIdentity.
        
        Returns:
            Test result with status and details
        """
        try:
            def _test():
                response = self._sts_client.get_caller_identity()
                return {
                    "account_id": response.get("Account"),
                    "user_id": response.get("UserId"),
                    "arn": response.get("Arn"),
                }
            
            loop = asyncio.get_event_loop()
            identity = await loop.run_in_executor(None, _test)
            
            credentials = await self.ensure_valid_credentials()
            
            return {
                "status": "success",
                "provider": self.provider_name,
                "authenticated": True,
                "expires_in": credentials.expires_in_seconds,
                "identity": identity,
            }
        except Exception as e:
            return {
                "status": "failed",
                "provider": self.provider_name,
                "authenticated": False,
                "error": str(e),
            }
    
    def get_boto3_session(self) -> boto3.Session:
        """
        Get the configured boto3 session.
        
        Returns:
            Boto3 session instance
        """
        if not self._session:
            raise RuntimeError("AWS authentication not initialized")
        return self._session
    
    async def get_boto3_client(self, service_name: str, **kwargs) -> Any:
        """
        Get a boto3 client for a specific service.
        
        Args:
            service_name: AWS service name (e.g., 'batch', 's3')
            **kwargs: Additional client arguments
            
        Returns:
            Boto3 service client
        """
        # Ensure credentials are fresh
        await self.ensure_valid_credentials()
        
        def _create_client():
            return self._session.client(service_name, **kwargs)
        
        loop = asyncio.get_event_loop()
        return await loop.run_in_executor(None, _create_client)
    
    async def get_boto3_resource(self, service_name: str, **kwargs) -> Any:
        """
        Get a boto3 resource for a specific service.
        
        Args:
            service_name: AWS service name (e.g., 's3', 'ec2')
            **kwargs: Additional resource arguments
            
        Returns:
            Boto3 service resource
        """
        # Ensure credentials are fresh
        await self.ensure_valid_credentials()
        
        def _create_resource():
            return self._session.resource(service_name, **kwargs)
        
        loop = asyncio.get_event_loop()
        return await loop.run_in_executor(None, _create_resource)