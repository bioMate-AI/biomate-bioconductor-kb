"""
Kubernetes authentication provider implementation.
"""

import os
from typing import Dict, Any, Optional

from kubernetes_asyncio import config
from kubernetes_asyncio.config import ConfigException

from galaxy_cloud.core.auth import CloudAuth, CloudCredentials
from galaxy_cloud.registry import cloud_auth


@cloud_auth("k8s", {
    "description": "Kubernetes authentication provider",
    "supported_methods": [
        "kubeconfig", "in_cluster", "service_account_token",
        "bearer_token", "username_password", "client_cert"
    ],
    "version": "1.0.0"
})
class K8sAuth(CloudAuth):
    """Kubernetes authentication provider."""
    
    def __init__(self, config: Dict[str, Any], **kwargs):
        super().__init__(config, **kwargs)
        
        # Kubernetes authentication configuration
        self.kubeconfig_path = config.get('kubeconfig_path') or os.getenv('KUBECONFIG')
        self.context = config.get('context')
        self.cluster_endpoint = config.get('cluster_endpoint')
        self.namespace = config.get('namespace', 'default')
        
        # Authentication method
        self.auth_method = config.get('auth_method', 'kubeconfig')
        
        # Token-based authentication
        self.bearer_token = config.get('bearer_token') or os.getenv('K8S_BEARER_TOKEN')
        self.service_account_token_path = config.get('service_account_token_path', '/var/run/secrets/kubernetes.io/serviceaccount/token')
        
        # Certificate-based authentication
        self.client_cert_file = config.get('client_cert_file')
        self.client_key_file = config.get('client_key_file')
        self.ca_cert_file = config.get('ca_cert_file')
        
        # Username/password authentication
        self.username = config.get('username')
        self.password = config.get('password')
        
        # Internal state
        self.k8s_config = None
        
    async def initialize(self) -> None:
        """Initialize Kubernetes authentication."""
        try:
            await self._load_kubernetes_config()
            
            self._initialized = True
            self.logger.info(f"Kubernetes authentication initialized using method: {self.auth_method}")
            
        except Exception as e:
            self.logger.error(f"Failed to initialize Kubernetes authentication: {e}")
            raise
    
    async def cleanup(self) -> None:
        """Clean up Kubernetes authentication resources."""
        self.k8s_config = None
        self._initialized = False
        self.logger.info("Kubernetes authentication cleaned up")
    
    @property
    def provider_name(self) -> str:
        return "k8s"
    
    async def get_credentials(self, force_refresh: bool = False) -> CloudCredentials:
        """Get Kubernetes credentials."""
        if not self._initialized:
            raise RuntimeError("Authentication provider not initialized")
        
        try:
            # Kubernetes config is already loaded
            credentials_data = {
                'auth_method': self.auth_method,
                'context': self.context,
                'cluster_endpoint': self.cluster_endpoint,
                'namespace': self.namespace,
                'kubeconfig_path': self.kubeconfig_path
            }
            
            return CloudCredentials(
                credentials_data,
                raw_credentials=self.k8s_config
            )
            
        except Exception as e:
            self.logger.error(f"Failed to get Kubernetes credentials: {e}")
            raise
    
    async def refresh_credentials(self) -> CloudCredentials:
        """Refresh Kubernetes credentials."""
        await self._load_kubernetes_config()
        return await self.get_credentials(force_refresh=True)
    
    # Private methods
    
    async def _load_kubernetes_config(self) -> None:
        """Load Kubernetes configuration based on authentication method."""
        
        if self.auth_method == 'kubeconfig':
            await self._load_kubeconfig()
        
        elif self.auth_method == 'in_cluster':
            await self._load_in_cluster_config()
        
        elif self.auth_method == 'service_account_token':
            await self._load_service_account_token()
        
        elif self.auth_method == 'bearer_token':
            await self._load_bearer_token()
        
        elif self.auth_method == 'client_cert':
            await self._load_client_cert()
        
        elif self.auth_method == 'username_password':
            await self._load_username_password()
        
        else:
            raise ValueError(f"Unsupported authentication method: {self.auth_method}")
    
    async def _load_kubeconfig(self) -> None:
        """Load configuration from kubeconfig file."""
        try:
            if self.kubeconfig_path:
                await config.load_kube_config(
                    config_file=self.kubeconfig_path,
                    context=self.context
                )
            else:
                await config.load_kube_config(context=self.context)
            
            self.logger.debug("Loaded kubeconfig authentication")
            
        except ConfigException as e:
            self.logger.error(f"Failed to load kubeconfig: {e}")
            raise
    
    async def _load_in_cluster_config(self) -> None:
        """Load in-cluster configuration."""
        try:
            config.load_incluster_config()
            self.logger.debug("Loaded in-cluster authentication")
            
        except ConfigException as e:
            self.logger.error(f"Failed to load in-cluster config: {e}")
            raise
    
    async def _load_service_account_token(self) -> None:
        """Load service account token authentication."""
        try:
            if not os.path.exists(self.service_account_token_path):
                raise FileNotFoundError(f"Service account token not found: {self.service_account_token_path}")
            
            with open(self.service_account_token_path, 'r') as f:
                token = f.read().strip()
            
            # Configure authentication with token
            configuration = config.Configuration()
            configuration.api_key['authorization'] = token
            configuration.api_key_prefix['authorization'] = 'Bearer'
            
            if self.cluster_endpoint:
                configuration.host = self.cluster_endpoint
            
            if self.ca_cert_file:
                configuration.ssl_ca_cert = self.ca_cert_file
            
            config.Configuration.set_default(configuration)
            
            self.logger.debug("Loaded service account token authentication")
            
        except Exception as e:
            self.logger.error(f"Failed to load service account token: {e}")
            raise
    
    async def _load_bearer_token(self) -> None:
        """Load bearer token authentication."""
        try:
            if not self.bearer_token:
                raise ValueError("Bearer token is required")
            
            configuration = config.Configuration()
            configuration.api_key['authorization'] = self.bearer_token
            configuration.api_key_prefix['authorization'] = 'Bearer'
            
            if self.cluster_endpoint:
                configuration.host = self.cluster_endpoint
            
            if self.ca_cert_file:
                configuration.ssl_ca_cert = self.ca_cert_file
            
            config.Configuration.set_default(configuration)
            
            self.logger.debug("Loaded bearer token authentication")
            
        except Exception as e:
            self.logger.error(f"Failed to load bearer token: {e}")
            raise
    
    async def _load_client_cert(self) -> None:
        """Load client certificate authentication."""
        try:
            if not all([self.client_cert_file, self.client_key_file]):
                raise ValueError("Client certificate and key files are required")
            
            configuration = config.Configuration()
            configuration.cert_file = self.client_cert_file
            configuration.key_file = self.client_key_file
            
            if self.cluster_endpoint:
                configuration.host = self.cluster_endpoint
            
            if self.ca_cert_file:
                configuration.ssl_ca_cert = self.ca_cert_file
            
            config.Configuration.set_default(configuration)
            
            self.logger.debug("Loaded client certificate authentication")
            
        except Exception as e:
            self.logger.error(f"Failed to load client certificate: {e}")
            raise
    
    async def _load_username_password(self) -> None:
        """Load username/password authentication."""
        try:
            if not all([self.username, self.password]):
                raise ValueError("Username and password are required")
            
            configuration = config.Configuration()
            configuration.username = self.username
            configuration.password = self.password
            
            if self.cluster_endpoint:
                configuration.host = self.cluster_endpoint
            
            if self.ca_cert_file:
                configuration.ssl_ca_cert = self.ca_cert_file
            
            config.Configuration.set_default(configuration)
            
            self.logger.debug("Loaded username/password authentication")
            
        except Exception as e:
            self.logger.error(f"Failed to load username/password: {e}")
            raise
    
    def get_credential_info(self) -> Dict[str, Any]:
        """Get information about the current credential configuration."""
        return {
            'auth_method': self.auth_method,
            'context': self.context,
            'cluster_endpoint': self.cluster_endpoint,
            'namespace': self.namespace,
            'kubeconfig_path': self.kubeconfig_path,
            'has_bearer_token': bool(self.bearer_token),
            'has_client_cert': bool(self.client_cert_file and self.client_key_file),
            'has_username_password': bool(self.username and self.password),
            'service_account_token_path': self.service_account_token_path
        }
    
    async def validate_access(self) -> Dict[str, bool]:
        """Validate access to Kubernetes cluster."""
        try:
            from kubernetes_asyncio import client
            
            permissions = {
                'cluster_access': False,
                'namespace_access': False,
                'can_create_pods': False,
                'can_create_jobs': False,
                'can_create_pvcs': False
            }
            
            try:
                # Test basic cluster access
                api_client = client.ApiClient()
                core_v1 = client.CoreV1Api(api_client)
                
                # Try to list namespaces (cluster-level permission)
                try:
                    await core_v1.list_namespace(limit=1)
                    permissions['cluster_access'] = True
                except:
                    pass
                
                # Try to access the configured namespace
                try:
                    await core_v1.read_namespace(name=self.namespace)
                    permissions['namespace_access'] = True
                except:
                    pass
                
                # Test resource creation permissions
                try:
                    # Check if we can list pods (implies read access)
                    await core_v1.list_namespaced_pod(namespace=self.namespace, limit=1)
                    permissions['can_create_pods'] = True
                except:
                    pass
                
                try:
                    # Check if we can list jobs
                    batch_v1 = client.BatchV1Api(api_client)
                    await batch_v1.list_namespaced_job(namespace=self.namespace, limit=1)
                    permissions['can_create_jobs'] = True
                except:
                    pass
                
                try:
                    # Check if we can list PVCs
                    await core_v1.list_namespaced_persistent_volume_claim(namespace=self.namespace, limit=1)
                    permissions['can_create_pvcs'] = True
                except:
                    pass
                
                await api_client.close()
                
            except Exception as e:
                self.logger.warning(f"Failed to validate cluster access: {e}")
            
            return permissions
            
        except Exception as e:
            self.logger.error(f"Failed to validate access: {e}")
            return {}
    
    async def get_cluster_info(self) -> Dict[str, Any]:
        """Get information about the Kubernetes cluster."""
        try:
            from kubernetes_asyncio import client
            
            api_client = client.ApiClient()
            core_v1 = client.CoreV1Api(api_client)
            
            try:
                # Get cluster version
                version_info = await api_client.call_api(
                    '/version', 'GET',
                    response_type='object'
                )
                
                # Get node information
                nodes = await core_v1.list_node(limit=5)
                
                cluster_info = {
                    'kubernetes_version': version_info[0].get('gitVersion', 'Unknown'),
                    'platform': version_info[0].get('platform', 'Unknown'),
                    'node_count': len(nodes.items),
                    'nodes': [
                        {
                            'name': node.metadata.name,
                            'version': node.status.node_info.kubelet_version,
                            'os': f"{node.status.node_info.os_image} ({node.status.node_info.architecture})",
                            'ready': any(
                                condition.type == 'Ready' and condition.status == 'True'
                                for condition in node.status.conditions or []
                            )
                        }
                        for node in nodes.items
                    ]
                }
                
                await api_client.close()
                return cluster_info
                
            except Exception as e:
                await api_client.close()
                return {'error': str(e)}
                
        except Exception as e:
            self.logger.error(f"Failed to get cluster info: {e}")
            return {'error': str(e)}
    
    async def list_namespaces(self) -> List[str]:
        """List available namespaces."""
        try:
            from kubernetes_asyncio import client
            
            api_client = client.ApiClient()
            core_v1 = client.CoreV1Api(api_client)
            
            try:
                namespaces = await core_v1.list_namespace()
                namespace_names = [ns.metadata.name for ns in namespaces.items]
                
                await api_client.close()
                return namespace_names
                
            except Exception as e:
                await api_client.close()
                self.logger.warning(f"Failed to list namespaces: {e}")
                return [self.namespace]  # Return at least the configured namespace
                
        except Exception as e:
            self.logger.error(f"Failed to list namespaces: {e}")
            return []