"""
Galaxy Workflow Configuration

Configuration management for Galaxy cloud workflow execution.
"""

import os
from pathlib import Path
from typing import Dict, Any, Optional
import yaml
from pydantic import BaseModel, Field


class GalaxyAPIConfig(BaseModel):
    """Galaxy API configuration"""
    url: str = Field(description="Galaxy instance URL")
    api_key: str = Field(description="Galaxy API key")
    verify_ssl: bool = Field(default=True, description="Verify SSL certificates")


class ToolRegistryConfig(BaseModel):
    """Tool registry configuration"""
    static_mappings_file: Optional[str] = Field(default=None, description="Static tool mappings file")
    biocontainers_api_url: str = Field(
        default="https://biocontainers.pro/api/ga4gh/trs/v2/tools",
        description="BioContainers API URL"
    )
    default_image: str = Field(
        default="quay.io/biocontainers/galaxy-minimal:latest",
        description="Default container image for unknown tools"
    )
    cache_ttl: int = Field(default=3600, description="Cache TTL in seconds")


class StorageConfig(BaseModel):
    """Storage configuration for different cloud providers"""
    aws: Optional[Dict[str, Any]] = Field(default=None)
    azure: Optional[Dict[str, Any]] = Field(default=None)
    gcp: Optional[Dict[str, Any]] = Field(default=None)
    kubernetes: Optional[Dict[str, Any]] = Field(default=None)


class CloudProviderConfig(BaseModel):
    """Cloud provider configuration"""
    aws: Optional[Dict[str, Any]] = Field(default=None)
    azure: Optional[Dict[str, Any]] = Field(default=None)
    gcp: Optional[Dict[str, Any]] = Field(default=None)
    kubernetes: Optional[Dict[str, Any]] = Field(default=None)


class GalaxyWorkflowConfig(BaseModel):
    """Complete Galaxy workflow configuration"""
    galaxy_api: Optional[GalaxyAPIConfig] = Field(default=None)
    tool_registry: ToolRegistryConfig = Field(default_factory=ToolRegistryConfig)
    storage: StorageConfig = Field(default_factory=StorageConfig)
    cloud_providers: CloudProviderConfig = Field(default_factory=CloudProviderConfig)

    # Global settings
    default_cloud_provider: str = Field(default="kubernetes", description="Default cloud provider")
    max_parallel_workflows: int = Field(default=10, description="Maximum parallel workflows")
    workflow_timeout: int = Field(default=86400, description="Default workflow timeout in seconds")
    cleanup_on_completion: bool = Field(default=True, description="Clean up cloud resources on completion")
    retain_intermediate_data: bool = Field(default=False, description="Retain intermediate data")

    class Config:
        extra = "allow"


def load_config_from_file(config_path: Path) -> GalaxyWorkflowConfig:
    """Load configuration from YAML file"""
    if not config_path.exists():
        raise FileNotFoundError(f"Configuration file not found: {config_path}")

    with open(config_path, 'r') as f:
        config_data = yaml.safe_load(f)

    return GalaxyWorkflowConfig(**config_data)


def load_config_from_env() -> GalaxyWorkflowConfig:
    """Load configuration from environment variables"""
    config_data = {}

    # Galaxy API configuration
    if os.getenv('GALAXY_URL') and os.getenv('GALAXY_API_KEY'):
        config_data['galaxy_api'] = {
            'url': os.getenv('GALAXY_URL'),
            'api_key': os.getenv('GALAXY_API_KEY'),
            'verify_ssl': os.getenv('GALAXY_VERIFY_SSL', 'true').lower() == 'true'
        }

    # Tool registry
    tool_registry_config = {}
    if os.getenv('TOOL_MAPPINGS_FILE'):
        tool_registry_config['static_mappings_file'] = os.getenv('TOOL_MAPPINGS_FILE')
    if os.getenv('BIOCONTAINERS_API_URL'):
        tool_registry_config['biocontainers_api_url'] = os.getenv('BIOCONTAINERS_API_URL')
    if os.getenv('DEFAULT_CONTAINER_IMAGE'):
        tool_registry_config['default_image'] = os.getenv('DEFAULT_CONTAINER_IMAGE')

    if tool_registry_config:
        config_data['tool_registry'] = tool_registry_config

    # Cloud providers
    cloud_providers = {}

    # AWS
    if os.getenv('AWS_REGION'):
        cloud_providers['aws'] = {
            'region': os.getenv('AWS_REGION'),
            'batch_queue': os.getenv('AWS_BATCH_QUEUE'),
            's3_bucket': os.getenv('AWS_S3_BUCKET'),
            'access_key_id': os.getenv('AWS_ACCESS_KEY_ID'),
            'secret_access_key': os.getenv('AWS_SECRET_ACCESS_KEY')
        }

    # Azure
    if os.getenv('AZURE_SUBSCRIPTION_ID'):
        cloud_providers['azure'] = {
            'subscription_id': os.getenv('AZURE_SUBSCRIPTION_ID'),
            'resource_group': os.getenv('AZURE_RESOURCE_GROUP'),
            'batch_account': os.getenv('AZURE_BATCH_ACCOUNT'),
            'storage_account': os.getenv('AZURE_STORAGE_ACCOUNT'),
            'tenant_id': os.getenv('AZURE_TENANT_ID'),
            'client_id': os.getenv('AZURE_CLIENT_ID'),
            'client_secret': os.getenv('AZURE_CLIENT_SECRET')
        }

    # GCP
    if os.getenv('GCP_PROJECT_ID'):
        cloud_providers['gcp'] = {
            'project_id': os.getenv('GCP_PROJECT_ID'),
            'region': os.getenv('GCP_REGION', 'us-central1'),
            'storage_bucket': os.getenv('GCP_STORAGE_BUCKET'),
            'service_account_key': os.getenv('GCP_SERVICE_ACCOUNT_KEY')
        }

    # Kubernetes
    if os.getenv('KUBECONFIG') or os.getenv('K8S_NAMESPACE'):
        cloud_providers['kubernetes'] = {
            'kubeconfig': os.getenv('KUBECONFIG'),
            'namespace': os.getenv('K8S_NAMESPACE', 'default'),
            'storage_class': os.getenv('K8S_STORAGE_CLASS'),
            'image_pull_secrets': os.getenv('K8S_IMAGE_PULL_SECRETS')
        }

    if cloud_providers:
        config_data['cloud_providers'] = cloud_providers

    # Storage configuration
    storage_config = {}
    if 's3_bucket' in cloud_providers.get('aws', {}):
        storage_config['aws'] = {
            'bucket_name': cloud_providers['aws']['s3_bucket'],
            'region': cloud_providers['aws']['region']
        }

    if cloud_providers.get('azure', {}).get('storage_account'):
        storage_config['azure'] = {
            'storage_account': cloud_providers['azure']['storage_account'],
            'container_name': os.getenv('AZURE_STORAGE_CONTAINER', 'galaxy-data')
        }

    if cloud_providers.get('gcp', {}).get('storage_bucket'):
        storage_config['gcp'] = {
            'project_id': cloud_providers['gcp']['project_id'],
            'bucket_name': cloud_providers['gcp']['storage_bucket']
        }

    if storage_config:
        config_data['storage'] = storage_config

    # Global settings
    if os.getenv('DEFAULT_CLOUD_PROVIDER'):
        config_data['default_cloud_provider'] = os.getenv('DEFAULT_CLOUD_PROVIDER')

    if os.getenv('MAX_PARALLEL_WORKFLOWS'):
        config_data['max_parallel_workflows'] = int(os.getenv('MAX_PARALLEL_WORKFLOWS'))

    if os.getenv('WORKFLOW_TIMEOUT'):
        config_data['workflow_timeout'] = int(os.getenv('WORKFLOW_TIMEOUT'))

    return GalaxyWorkflowConfig(**config_data)


def get_default_config() -> GalaxyWorkflowConfig:
    """Get default configuration"""
    return GalaxyWorkflowConfig()


def save_config_to_file(config: GalaxyWorkflowConfig, config_path: Path):
    """Save configuration to YAML file"""
    config_dict = config.dict(exclude_none=True)

    with open(config_path, 'w') as f:
        yaml.dump(config_dict, f, default_flow_style=False, sort_keys=True)