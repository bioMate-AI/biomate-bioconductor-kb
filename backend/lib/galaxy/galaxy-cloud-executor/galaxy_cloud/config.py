"""
Configuration management system for Galaxy Cloud Executor.
Provides type-safe configuration with validation and environment variable support.
"""

import os
import yaml
from pathlib import Path
from typing import Dict, Any, Optional, Union, List
from pydantic import BaseModel, Field, validator, root_validator
from enum import Enum


class LogLevel(str, Enum):
    """Logging levels."""
    DEBUG = "debug"
    INFO = "info"
    WARNING = "warning"
    ERROR = "error"
    CRITICAL = "critical"


class RetryConfig(BaseModel):
    """Retry configuration."""
    max_attempts: int = Field(default=3, ge=1, le=10, description="Maximum retry attempts")
    initial_delay: float = Field(default=1.0, ge=0.1, description="Initial delay in seconds")
    max_delay: float = Field(default=60.0, ge=1.0, description="Maximum delay in seconds")
    exponential_base: float = Field(default=2.0, ge=1.1, description="Exponential backoff base")
    jitter: float = Field(default=0.1, ge=0.0, le=1.0, description="Jitter factor")
    
    class Config:
        extra = "forbid"


class ResourceLimits(BaseModel):
    """Resource limits configuration."""
    max_cpus: Optional[int] = Field(default=None, ge=1, description="Maximum CPU cores")
    max_memory_mb: Optional[int] = Field(default=None, ge=1, description="Maximum memory in MB")
    max_disk_gb: Optional[int] = Field(default=None, ge=1, description="Maximum disk in GB")
    max_concurrent_jobs: int = Field(default=100, ge=1, description="Maximum concurrent jobs")
    
    class Config:
        extra = "forbid"


class AWSConfig(BaseModel):
    """AWS-specific configuration."""
    enabled: bool = Field(default=False, description="Enable AWS provider")
    region: str = Field(default="us-east-1", description="AWS region")
    
    # Authentication
    access_key_id: Optional[str] = Field(default=None, description="AWS access key ID")
    secret_access_key: Optional[str] = Field(default=None, description="AWS secret access key")
    session_token: Optional[str] = Field(default=None, description="AWS session token")
    profile: Optional[str] = Field(default=None, description="AWS profile name")
    role_arn: Optional[str] = Field(default=None, description="IAM role ARN to assume")
    
    # Batch configuration
    batch_queue: Optional[str] = Field(default=None, description="AWS Batch job queue")
    batch_compute_environment: Optional[str] = Field(default=None, description="Batch compute environment")
    batch_job_definition: Optional[str] = Field(default=None, description="Default job definition")
    
    # EC2 configuration
    instance_types: List[str] = Field(default_factory=lambda: ["m5.large"], description="Allowed instance types")
    spot_allocation: str = Field(default="onDemand", description="Spot fleet allocation strategy")
    max_spot_attempts: int = Field(default=3, ge=0, description="Maximum spot retry attempts")
    
    # S3 configuration
    s3_bucket: Optional[str] = Field(default=None, description="Default S3 bucket")
    s3_prefix: str = Field(default="galaxy-cloud-executor", description="S3 key prefix")
    s3_storage_class: str = Field(default="STANDARD", description="S3 storage class")
    
    # Resource limits
    resource_limits: ResourceLimits = Field(default_factory=ResourceLimits)
    
    # Retry configuration
    retry_config: RetryConfig = Field(default_factory=RetryConfig)
    
    class Config:
        extra = "forbid"


class AzureConfig(BaseModel):
    """Azure-specific configuration."""
    enabled: bool = Field(default=False, description="Enable Azure provider")
    
    # Authentication
    subscription_id: Optional[str] = Field(default=None, description="Azure subscription ID")
    tenant_id: Optional[str] = Field(default=None, description="Azure tenant ID")
    client_id: Optional[str] = Field(default=None, description="Azure client ID")
    client_secret: Optional[str] = Field(default=None, description="Azure client secret")
    
    # Batch configuration
    batch_account: Optional[str] = Field(default=None, description="Azure Batch account")
    batch_pool: Optional[str] = Field(default=None, description="Default batch pool")
    batch_location: str = Field(default="eastus", description="Batch account location")
    
    # VM configuration
    vm_sizes: List[str] = Field(default_factory=lambda: ["Standard_D2s_v3"], description="Allowed VM sizes")
    low_priority_percentage: int = Field(default=50, ge=0, le=100, description="Low priority VM percentage")
    
    # Storage configuration
    storage_account: Optional[str] = Field(default=None, description="Storage account name")
    storage_container: str = Field(default="galaxy-data", description="Default container name")
    sas_token_duration: int = Field(default=3600, ge=300, description="SAS token duration in seconds")
    
    # Resource limits
    resource_limits: ResourceLimits = Field(default_factory=ResourceLimits)
    
    # Retry configuration
    retry_config: RetryConfig = Field(default_factory=RetryConfig)
    
    class Config:
        extra = "forbid"


class GCPConfig(BaseModel):
    """Google Cloud Platform configuration."""
    enabled: bool = Field(default=False, description="Enable GCP provider")
    project_id: Optional[str] = Field(default=None, description="GCP project ID")
    region: str = Field(default="us-central1", description="GCP region")
    zone: Optional[str] = Field(default=None, description="GCP zone")
    
    # Authentication
    service_account_file: Optional[str] = Field(default=None, description="Service account JSON file path")
    
    # Batch configuration
    batch_location: str = Field(default="us-central1", description="Batch service location")
    
    # Compute configuration
    machine_types: List[str] = Field(default_factory=lambda: ["e2-standard-2"], description="Allowed machine types")
    preemptible_percentage: int = Field(default=50, ge=0, le=100, description="Preemptible instance percentage")
    
    # Storage configuration
    storage_bucket: Optional[str] = Field(default=None, description="Default GCS bucket")
    storage_prefix: str = Field(default="galaxy-cloud-executor", description="Storage prefix")
    storage_class: str = Field(default="STANDARD", description="Storage class")
    
    # Resource limits
    resource_limits: ResourceLimits = Field(default_factory=ResourceLimits)
    
    # Retry configuration
    retry_config: RetryConfig = Field(default_factory=RetryConfig)
    
    class Config:
        extra = "forbid"


class KubernetesConfig(BaseModel):
    """Kubernetes configuration."""
    enabled: bool = Field(default=False, description="Enable Kubernetes provider")
    
    # Connection
    kubeconfig_path: Optional[str] = Field(default=None, description="Kubeconfig file path")
    context: Optional[str] = Field(default=None, description="Kubernetes context")
    namespace: str = Field(default="default", description="Kubernetes namespace")
    
    # Authentication
    service_account: Optional[str] = Field(default=None, description="Service account name")
    
    # Job configuration
    job_template: Dict[str, Any] = Field(default_factory=dict, description="Default job template")
    pod_template: Dict[str, Any] = Field(default_factory=dict, description="Default pod template")
    
    # Storage configuration
    storage_class: Optional[str] = Field(default=None, description="Storage class for PVCs")
    volume_claims: List[str] = Field(default_factory=list, description="Available volume claims")
    
    # Resource limits
    resource_limits: ResourceLimits = Field(default_factory=ResourceLimits)
    
    # Retry configuration
    retry_config: RetryConfig = Field(default_factory=RetryConfig)
    
    class Config:
        extra = "forbid"


class SecurityConfig(BaseModel):
    """Security configuration."""
    enable_encryption: bool = Field(default=True, description="Enable encryption at rest")
    enable_tls: bool = Field(default=True, description="Enable TLS for connections")
    secret_backend: str = Field(default="env", description="Secret backend type")
    vault_url: Optional[str] = Field(default=None, description="HashiCorp Vault URL")
    vault_token: Optional[str] = Field(default=None, description="Vault token")
    
    class Config:
        extra = "forbid"


class MonitoringConfig(BaseModel):
    """Monitoring and observability configuration."""
    enable_metrics: bool = Field(default=True, description="Enable metrics collection")
    enable_tracing: bool = Field(default=False, description="Enable distributed tracing")
    metrics_port: int = Field(default=8080, ge=1024, le=65535, description="Metrics endpoint port")
    log_level: LogLevel = Field(default=LogLevel.INFO, description="Logging level")
    structured_logging: bool = Field(default=True, description="Enable structured logging")
    
    # Prometheus configuration
    prometheus_endpoint: Optional[str] = Field(default=None, description="Prometheus endpoint")
    prometheus_job: str = Field(default="galaxy-cloud-executor", description="Prometheus job name")
    
    # Jaeger configuration  
    jaeger_endpoint: Optional[str] = Field(default=None, description="Jaeger endpoint")
    jaeger_service_name: str = Field(default="galaxy-cloud-executor", description="Jaeger service name")
    
    class Config:
        extra = "forbid"


class CloudConfig(BaseModel):
    """Complete cloud configuration."""
    
    # Provider configurations
    aws: AWSConfig = Field(default_factory=AWSConfig)
    azure: AzureConfig = Field(default_factory=AzureConfig)
    gcp: GCPConfig = Field(default_factory=GCPConfig)
    kubernetes: KubernetesConfig = Field(default_factory=KubernetesConfig)
    
    # Global settings
    default_provider: Optional[str] = Field(default=None, description="Default cloud provider")
    enable_auto_discovery: bool = Field(default=True, description="Enable automatic provider discovery")
    
    # Operation settings
    job_timeout_seconds: int = Field(default=3600, ge=60, description="Default job timeout")
    poll_interval_seconds: float = Field(default=30.0, ge=5.0, description="Status polling interval")
    cleanup_completed_jobs: bool = Field(default=True, description="Auto-cleanup completed jobs")
    
    # Security and monitoring
    security: SecurityConfig = Field(default_factory=SecurityConfig)
    monitoring: MonitoringConfig = Field(default_factory=MonitoringConfig)
    
    class Config:
        extra = "forbid"
    
    @root_validator(pre=False, skip_on_failure=True)
    def validate_default_provider(cls, values):
        """Validate that default provider is enabled."""
        default_provider = values.get('default_provider')
        if default_provider:
            provider_config = values.get(default_provider)
            if not provider_config or not provider_config.enabled:
                raise ValueError(f"Default provider '{default_provider}' is not enabled")
        return values
    
    @validator('default_provider')
    def validate_provider_name(cls, v):
        """Validate provider name."""
        if v and v not in ['aws', 'azure', 'gcp', 'kubernetes']:
            raise ValueError(f"Invalid provider name: {v}")
        return v
    
    def get_enabled_providers(self) -> List[str]:
        """Get list of enabled providers."""
        enabled = []
        if self.aws.enabled:
            enabled.append('aws')
        if self.azure.enabled:
            enabled.append('azure')
        if self.gcp.enabled:
            enabled.append('gcp')
        if self.kubernetes.enabled:
            enabled.append('kubernetes')
        return enabled
    
    def get_provider_config(self, provider: str) -> Optional[BaseModel]:
        """Get configuration for a specific provider."""
        return getattr(self, provider, None)


class ConfigManager:
    """Configuration manager with environment variable support and validation."""
    
    def __init__(self, config_file: Optional[Union[str, Path]] = None):
        """
        Initialize configuration manager.
        
        Args:
            config_file: Optional configuration file path
        """
        self.config_file = Path(config_file) if config_file else None
        self._config: Optional[CloudConfig] = None
    
    def load_config(self, config_file: Optional[Union[str, Path]] = None) -> CloudConfig:
        """
        Load configuration from file with environment variable substitution.
        
        Args:
            config_file: Configuration file path
            
        Returns:
            Loaded configuration
        """
        if config_file:
            self.config_file = Path(config_file)
        
        if self.config_file and self.config_file.exists():
            # Load from YAML file
            with open(self.config_file, 'r') as f:
                config_data = yaml.safe_load(f)
            
            # Substitute environment variables
            config_data = self._substitute_env_vars(config_data)
            
            # Validate and create config
            self._config = CloudConfig(**config_data)
        else:
            # Load from environment variables only
            self._config = self._load_from_env()
        
        return self._config
    
    def save_config(self, config: CloudConfig, config_file: Optional[Union[str, Path]] = None) -> None:
        """
        Save configuration to file.
        
        Args:
            config: Configuration to save
            config_file: Optional file path to save to
        """
        if config_file:
            self.config_file = Path(config_file)
        
        if not self.config_file:
            raise ValueError("No config file specified")
        
        # Ensure parent directory exists
        self.config_file.parent.mkdir(parents=True, exist_ok=True)
        
        # Convert to dict and save as YAML
        config_dict = config.dict()
        with open(self.config_file, 'w') as f:
            yaml.dump(config_dict, f, default_flow_style=False, indent=2)
    
    def get_config(self) -> CloudConfig:
        """Get current configuration."""
        if self._config is None:
            self._config = self.load_config()
        return self._config
    
    def reload_config(self) -> CloudConfig:
        """Reload configuration from file."""
        self._config = None
        return self.load_config()
    
    def _substitute_env_vars(self, data: Any) -> Any:
        """
        Recursively substitute environment variables in configuration data.
        
        Supports ${VAR_NAME} and ${VAR_NAME:default_value} syntax.
        """
        if isinstance(data, dict):
            return {key: self._substitute_env_vars(value) for key, value in data.items()}
        elif isinstance(data, list):
            return [self._substitute_env_vars(item) for item in data]
        elif isinstance(data, str):
            return self._substitute_string_vars(data)
        else:
            return data
    
    def _substitute_string_vars(self, text: str) -> str:
        """Substitute environment variables in a string."""
        import re
        
        # Pattern for ${VAR_NAME} or ${VAR_NAME:default}
        pattern = r'\$\{([^}:]+)(?::([^}]*))?\}'
        
        def replace_match(match):
            var_name = match.group(1)
            default_value = match.group(2)
            return os.getenv(var_name, default_value or '')
        
        return re.sub(pattern, replace_match, text)
    
    def _load_from_env(self) -> CloudConfig:
        """Load configuration from environment variables."""
        config_data = {}
        
        # AWS configuration
        if any(os.getenv(var) for var in ['AWS_ACCESS_KEY_ID', 'AWS_PROFILE', 'GALAXY_AWS_ENABLED']):
            config_data['aws'] = {
                'enabled': os.getenv('GALAXY_AWS_ENABLED', 'false').lower() == 'true',
                'region': os.getenv('AWS_DEFAULT_REGION', 'us-east-1'),
                'access_key_id': os.getenv('AWS_ACCESS_KEY_ID'),
                'secret_access_key': os.getenv('AWS_SECRET_ACCESS_KEY'),
                'session_token': os.getenv('AWS_SESSION_TOKEN'),
                'profile': os.getenv('AWS_PROFILE'),
                'batch_queue': os.getenv('GALAXY_AWS_BATCH_QUEUE'),
                's3_bucket': os.getenv('GALAXY_AWS_S3_BUCKET'),
            }
        
        # Azure configuration
        if any(os.getenv(var) for var in ['AZURE_CLIENT_ID', 'AZURE_SUBSCRIPTION_ID', 'GALAXY_AZURE_ENABLED']):
            config_data['azure'] = {
                'enabled': os.getenv('GALAXY_AZURE_ENABLED', 'false').lower() == 'true',
                'subscription_id': os.getenv('AZURE_SUBSCRIPTION_ID'),
                'tenant_id': os.getenv('AZURE_TENANT_ID'),
                'client_id': os.getenv('AZURE_CLIENT_ID'),
                'client_secret': os.getenv('AZURE_CLIENT_SECRET'),
                'batch_account': os.getenv('GALAXY_AZURE_BATCH_ACCOUNT'),
                'storage_account': os.getenv('GALAXY_AZURE_STORAGE_ACCOUNT'),
            }
        
        # GCP configuration
        if any(os.getenv(var) for var in ['GOOGLE_APPLICATION_CREDENTIALS', 'GALAXY_GCP_ENABLED']):
            config_data['gcp'] = {
                'enabled': os.getenv('GALAXY_GCP_ENABLED', 'false').lower() == 'true',
                'project_id': os.getenv('GOOGLE_CLOUD_PROJECT'),
                'service_account_file': os.getenv('GOOGLE_APPLICATION_CREDENTIALS'),
                'storage_bucket': os.getenv('GALAXY_GCP_STORAGE_BUCKET'),
            }
        
        # Kubernetes configuration
        if any(os.getenv(var) for var in ['KUBECONFIG', 'KUBERNETES_SERVICE_HOST', 'GALAXY_K8S_ENABLED']):
            config_data['kubernetes'] = {
                'enabled': os.getenv('GALAXY_K8S_ENABLED', 'false').lower() == 'true',
                'kubeconfig_path': os.getenv('KUBECONFIG'),
                'namespace': os.getenv('GALAXY_K8S_NAMESPACE', 'default'),
                'context': os.getenv('GALAXY_K8S_CONTEXT'),
            }
        
        # Global settings
        config_data['default_provider'] = os.getenv('GALAXY_DEFAULT_CLOUD_PROVIDER')
        config_data['monitoring'] = {
            'log_level': os.getenv('GALAXY_LOG_LEVEL', 'info'),
            'enable_metrics': os.getenv('GALAXY_ENABLE_METRICS', 'true').lower() == 'true',
        }
        
        return CloudConfig(**config_data)


# Convenience functions

def load_config(config_file: Optional[Union[str, Path]] = None) -> CloudConfig:
    """
    Load configuration from file or environment variables.
    
    Args:
        config_file: Optional configuration file path
        
    Returns:
        Loaded configuration
    """
    manager = ConfigManager(config_file)
    return manager.load_config()


def create_default_config() -> CloudConfig:
    """Create a default configuration with all providers disabled."""
    return CloudConfig()


def validate_config(config_data: Dict[str, Any]) -> CloudConfig:
    """
    Validate configuration data.
    
    Args:
        config_data: Configuration dictionary
        
    Returns:
        Validated configuration
        
    Raises:
        ValidationError: If configuration is invalid
    """
    return CloudConfig(**config_data)