"""
Tests for configuration management.
"""

import pytest
import tempfile
import yaml
from pathlib import Path

from galaxy_cloud.config import (
    CloudConfig, 
    ConfigManager, 
    AWSConfig, 
    create_default_config,
    validate_config
)


class TestCloudConfig:
    """Test CloudConfig model."""
    
    def test_default_config(self):
        """Test default configuration creation."""
        config = CloudConfig()
        
        assert not config.aws.enabled
        assert not config.azure.enabled
        assert not config.gcp.enabled
        assert not config.kubernetes.enabled
        assert config.default_provider is None
        assert config.get_enabled_providers() == []
    
    def test_aws_config(self):
        """Test AWS configuration."""
        config = CloudConfig(
            aws=AWSConfig(
                enabled=True,
                region='us-west-2',
                batch_queue='test-queue',
                s3_bucket='test-bucket'
            ),
            default_provider='aws'
        )
        
        assert config.aws.enabled
        assert config.aws.region == 'us-west-2'
        assert config.aws.batch_queue == 'test-queue'
        assert config.aws.s3_bucket == 'test-bucket'
        assert config.default_provider == 'aws'
        assert config.get_enabled_providers() == ['aws']
    
    def test_get_provider_config(self):
        """Test getting provider configuration."""
        config = CloudConfig(
            aws=AWSConfig(enabled=True, region='us-east-1')
        )
        
        aws_config = config.get_provider_config('aws')
        assert aws_config is not None
        assert aws_config.enabled
        assert aws_config.region == 'us-east-1'
        
        azure_config = config.get_provider_config('azure')
        assert azure_config is not None
        assert not azure_config.enabled
    
    def test_invalid_default_provider(self):
        """Test validation of default provider."""
        with pytest.raises(ValueError, match="Invalid provider name"):
            CloudConfig(default_provider='invalid')
    
    def test_disabled_default_provider(self):
        """Test validation when default provider is disabled."""
        with pytest.raises(ValueError, match="Default provider 'aws' is not enabled"):
            CloudConfig(
                aws=AWSConfig(enabled=False),
                default_provider='aws'
            )


class TestConfigManager:
    """Test ConfigManager functionality."""
    
    def test_load_default_config(self):
        """Test loading default configuration."""
        manager = ConfigManager()
        config = manager.load_config()
        
        assert isinstance(config, CloudConfig)
        assert not config.aws.enabled
    
    def test_load_from_yaml_file(self):
        """Test loading configuration from YAML file."""
        config_data = {
            'aws': {
                'enabled': True,
                'region': 'us-east-1',
                'batch_queue': 'test-queue'
            },
            'default_provider': 'aws'
        }
        
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            yaml.dump(config_data, f)
            config_file = Path(f.name)
        
        try:
            manager = ConfigManager(config_file)
            config = manager.load_config()
            
            assert config.aws.enabled
            assert config.aws.region == 'us-east-1'
            assert config.aws.batch_queue == 'test-queue'
            assert config.default_provider == 'aws'
        finally:
            config_file.unlink()
    
    def test_save_config(self):
        """Test saving configuration to file."""
        config = CloudConfig(
            aws=AWSConfig(
                enabled=True,
                region='us-west-2',
                batch_queue='save-test-queue'
            )
        )
        
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            config_file = Path(f.name)
        
        try:
            manager = ConfigManager(config_file)
            manager.save_config(config)
            
            # Load back and verify
            loaded_config = manager.load_config()
            assert loaded_config.aws.enabled
            assert loaded_config.aws.region == 'us-west-2'
            assert loaded_config.aws.batch_queue == 'save-test-queue'
        finally:
            config_file.unlink()
    
    def test_environment_variable_substitution(self):
        """Test environment variable substitution."""
        import os
        
        # Set test environment variable
        os.environ['TEST_REGION'] = 'us-central-1'
        os.environ['TEST_QUEUE'] = 'env-test-queue'
        
        config_data = {
            'aws': {
                'enabled': True,
                'region': '${TEST_REGION}',
                'batch_queue': '${TEST_QUEUE}',
                'unknown_var': '${UNKNOWN_VAR:default_value}'
            }
        }
        
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            yaml.dump(config_data, f)
            config_file = Path(f.name)
        
        try:
            manager = ConfigManager(config_file)
            config = manager.load_config()
            
            assert config.aws.region == 'us-central-1'
            assert config.aws.batch_queue == 'env-test-queue'
            # Note: unknown_var would be in cloud_options or similar
        finally:
            config_file.unlink()
            # Clean up environment
            del os.environ['TEST_REGION']
            del os.environ['TEST_QUEUE']
    
    def test_reload_config(self):
        """Test configuration reloading."""
        config_data = {
            'aws': {
                'enabled': True,
                'region': 'us-east-1'
            }
        }
        
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            yaml.dump(config_data, f)
            config_file = Path(f.name)
        
        try:
            manager = ConfigManager(config_file)
            
            # Load initial config
            config1 = manager.load_config()
            assert config1.aws.region == 'us-east-1'
            
            # Modify file
            config_data['aws']['region'] = 'us-west-2'
            with open(config_file, 'w') as f:
                yaml.dump(config_data, f)
            
            # Reload
            config2 = manager.reload_config()
            assert config2.aws.region == 'us-west-2'
        finally:
            config_file.unlink()


class TestResourceLimits:
    """Test resource limits configuration."""
    
    def test_resource_limits_validation(self):
        """Test resource limits validation."""
        config = CloudConfig(
            aws=AWSConfig(
                enabled=True,
                resource_limits={
                    'max_cpus': 64,
                    'max_memory_mb': 128000,
                    'max_concurrent_jobs': 50
                }
            )
        )
        
        assert config.aws.resource_limits.max_cpus == 64
        assert config.aws.resource_limits.max_memory_mb == 128000
        assert config.aws.resource_limits.max_concurrent_jobs == 50
    
    def test_invalid_resource_limits(self):
        """Test validation of invalid resource limits."""
        with pytest.raises(ValueError):
            # Negative values should be rejected
            CloudConfig(
                aws=AWSConfig(
                    resource_limits={'max_cpus': -1}
                )
            )


class TestRetryConfig:
    """Test retry configuration."""
    
    def test_retry_config_defaults(self):
        """Test retry configuration defaults."""
        config = CloudConfig()
        
        retry_config = config.aws.retry_config
        assert retry_config.max_attempts == 3
        assert retry_config.initial_delay == 1.0
        assert retry_config.max_delay == 60.0
        assert retry_config.exponential_base == 2.0
        assert retry_config.jitter == 0.1
    
    def test_custom_retry_config(self):
        """Test custom retry configuration."""
        config = CloudConfig(
            aws=AWSConfig(
                retry_config={
                    'max_attempts': 5,
                    'initial_delay': 2.0,
                    'max_delay': 120.0,
                    'exponential_base': 1.5,
                    'jitter': 0.2
                }
            )
        )
        
        retry_config = config.aws.retry_config
        assert retry_config.max_attempts == 5
        assert retry_config.initial_delay == 2.0
        assert retry_config.max_delay == 120.0
        assert retry_config.exponential_base == 1.5
        assert retry_config.jitter == 0.2


class TestConfigValidation:
    """Test configuration validation functions."""
    
    def test_validate_config_success(self):
        """Test successful configuration validation."""
        config_data = {
            'aws': {
                'enabled': True,
                'region': 'us-east-1',
                'batch_queue': 'test-queue'
            }
        }
        
        config = validate_config(config_data)
        assert isinstance(config, CloudConfig)
        assert config.aws.enabled
    
    def test_validate_config_failure(self):
        """Test configuration validation failure."""
        config_data = {
            'aws': {
                'enabled': True,
                'region': 'us-east-1',
                'resource_limits': {
                    'max_cpus': -1  # Invalid
                }
            }
        }
        
        with pytest.raises(ValueError):
            validate_config(config_data)
    
    def test_create_default_config(self):
        """Test create_default_config function."""
        config = create_default_config()
        
        assert isinstance(config, CloudConfig)
        assert not config.aws.enabled
        assert not config.azure.enabled
        assert not config.gcp.enabled
        assert not config.kubernetes.enabled


class TestMonitoringConfig:
    """Test monitoring configuration."""
    
    def test_monitoring_defaults(self):
        """Test monitoring configuration defaults."""
        config = CloudConfig()
        
        monitoring = config.monitoring
        assert monitoring.enable_metrics
        assert not monitoring.enable_tracing
        assert monitoring.log_level == 'info'
        assert monitoring.structured_logging
        assert monitoring.metrics_port == 8080
    
    def test_custom_monitoring_config(self):
        """Test custom monitoring configuration."""
        config = CloudConfig(
            monitoring={
                'enable_metrics': False,
                'enable_tracing': True,
                'log_level': 'debug',
                'prometheus_endpoint': 'http://prometheus:9090'
            }
        )
        
        monitoring = config.monitoring
        assert not monitoring.enable_metrics
        assert monitoring.enable_tracing
        assert monitoring.log_level == 'debug'
        assert monitoring.prometheus_endpoint == 'http://prometheus:9090'