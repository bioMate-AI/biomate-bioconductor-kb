"""
Basic usage example for Galaxy Cloud Executor.
"""

import asyncio
import logging
from pathlib import Path

from galaxy_cloud import CloudExecutorFactory, CloudConfig
from galaxy_cloud.core.job import JobSpec, ResourceSpec, ContainerSpec
from galaxy_cloud.config import ConfigManager

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


async def basic_aws_example():
    """Basic AWS Batch example."""
    # Create configuration
    config = CloudConfig(
        aws={
            'enabled': True,
            'region': 'us-east-1',
            'batch_queue': 'your-batch-queue',  # Replace with your queue
            's3_bucket': 'your-s3-bucket',      # Replace with your bucket
        },
        default_provider='aws'
    )
    
    # Create executor
    executor = CloudExecutorFactory.create('aws-batch', config.aws.dict())
    
    # Define job specification
    job_spec = JobSpec(
        job_id='example-001',
        name='Hello World Job',
        container=ContainerSpec(
            image='ubuntu:20.04',
            command=['/bin/bash', '-c'],
            args=['echo "Hello from AWS Batch!"'],
            env={'JOB_TYPE': 'example'}
        ),
        resources=ResourceSpec(
            cpus=1,
            memory_mb=1024
        ),
        timeout_seconds=300
    )
    
    # Submit and monitor job
    async with executor:
        logger.info("Submitting job to AWS Batch...")
        cloud_job_id = await executor.submit_job(job_spec)
        logger.info(f"Job submitted with ID: {cloud_job_id}")
        
        # Wait for completion
        logger.info("Waiting for job completion...")
        result = await executor.wait_for_completion(cloud_job_id, poll_interval=10.0)
        
        logger.info(f"Job completed with status: {result.status}")
        logger.info(f"Exit code: {result.exit_code}")
        if result.stdout:
            logger.info(f"Output: {result.stdout}")


async def config_file_example():
    """Example using configuration file."""
    # Load configuration from file
    config_manager = ConfigManager('cloud_config.yaml')
    
    try:
        cloud_config = config_manager.load_config()
        logger.info("Configuration loaded from file")
    except FileNotFoundError:
        # Create default configuration
        cloud_config = CloudConfig()
        logger.info("Using default configuration")
    
    # Get enabled providers
    enabled_providers = cloud_config.get_enabled_providers()
    logger.info(f"Enabled providers: {enabled_providers}")
    
    if not enabled_providers:
        logger.warning("No providers enabled in configuration")
        return
    
    # Use first enabled provider
    provider = enabled_providers[0]
    provider_config = cloud_config.get_provider_config(provider)
    
    # Create executor based on provider
    if provider == 'aws':
        executor = CloudExecutorFactory.create('aws-batch', provider_config.dict())
    else:
        logger.warning(f"Provider {provider} not supported in this example")
        return
    
    # Create a simple job
    job_spec = JobSpec(
        job_id='config-example-001',
        name='Configuration Example',
        container=ContainerSpec(
            image='alpine:latest',
            command=['echo'],
            args=['Configuration example completed successfully!']
        ),
        resources=ResourceSpec(cpus=1, memory_mb=512)
    )
    
    # Submit job
    async with executor:
        cloud_job_id = await executor.submit_job(job_spec)
        logger.info(f"Job submitted: {cloud_job_id}")
        
        # Poll status
        while True:
            status = await executor.get_job_status(cloud_job_id)
            logger.info(f"Job status: {status}")
            
            if status in ['completed', 'failed', 'cancelled']:
                break
            
            await asyncio.sleep(10)
        
        # Get final result
        result = await executor.get_job_result(cloud_job_id)
        logger.info(f"Final result: {result.status}")


async def batch_jobs_example():
    """Example submitting multiple jobs."""
    # Configuration
    config = CloudConfig(
        aws={
            'enabled': True,
            'region': 'us-east-1',
            'batch_queue': 'your-batch-queue',
        }
    )
    
    executor = CloudExecutorFactory.create('aws-batch', config.aws.dict())
    
    # Create multiple job specifications
    job_specs = []
    for i in range(3):
        job_spec = JobSpec(
            job_id=f'batch-job-{i:03d}',
            name=f'Batch Job {i}',
            container=ContainerSpec(
                image='ubuntu:20.04',
                command=['/bin/bash', '-c'],
                args=[f'echo "This is job {i}"; sleep 60; echo "Job {i} completed"']
            ),
            resources=ResourceSpec(cpus=1, memory_mb=512)
        )
        job_specs.append(job_spec)
    
    # Submit all jobs
    async with executor:
        logger.info("Submitting batch jobs...")
        job_ids = await executor.bulk_submit(job_specs)
        logger.info(f"Submitted {len(job_ids)} jobs: {job_ids}")
        
        # Monitor all jobs
        while True:
            statuses = await executor.bulk_status(job_ids)
            
            # Log current status
            status_counts = {}
            for job_id, status in statuses.items():
                status_counts[status] = status_counts.get(status, 0) + 1
            
            logger.info(f"Job status summary: {status_counts}")
            
            # Check if all jobs are complete
            if all(status in ['completed', 'failed', 'cancelled'] for status in statuses.values()):
                logger.info("All jobs completed")
                break
            
            await asyncio.sleep(30)


async def monitoring_example():
    """Example with job monitoring and events."""
    config = CloudConfig(
        aws={
            'enabled': True,
            'region': 'us-east-1',
            'batch_queue': 'your-batch-queue',
        }
    )
    
    executor = CloudExecutorFactory.create('aws-batch', config.aws.dict())
    
    job_spec = JobSpec(
        job_id='monitoring-example-001',
        name='Monitoring Example',
        container=ContainerSpec(
            image='ubuntu:20.04',
            command=['/bin/bash', '-c'],
            args=['for i in {1..10}; do echo "Step $i"; sleep 10; done; echo "Completed!"']
        ),
        resources=ResourceSpec(cpus=1, memory_mb=512)
    )
    
    async with executor:
        # Submit job
        cloud_job_id = await executor.submit_job(job_spec)
        logger.info(f"Monitoring job: {cloud_job_id}")
        
        # Monitor with events
        async with executor.job_monitor(cloud_job_id, poll_interval=15.0) as monitor:
            async for event in monitor:
                logger.info(f"Job event: {event.event_type} - {event.message}")
                
                if event.event_type == 'status_change':
                    new_status = event.details.get('new_status')
                    if new_status in ['completed', 'failed', 'cancelled']:
                        break


def create_sample_config():
    """Create a sample configuration file."""
    config = CloudConfig(
        aws={
            'enabled': True,
            'region': 'us-east-1',
            'batch_queue': 'my-batch-queue',
            's3_bucket': 'my-s3-bucket',
            'resource_limits': {
                'max_cpus': 64,
                'max_memory_mb': 128000,
                'max_concurrent_jobs': 50
            }
        },
        monitoring={
            'log_level': 'info',
            'enable_metrics': True
        }
    )
    
    config_manager = ConfigManager('cloud_config.yaml')
    config_manager.save_config(config)
    logger.info("Sample configuration saved to cloud_config.yaml")


async def main():
    """Run examples."""
    logger.info("Galaxy Cloud Executor Examples")
    
    # Create sample configuration
    create_sample_config()
    
    try:
        # Run basic example (uncomment to test with real AWS credentials)
        # await basic_aws_example()
        
        # Run configuration file example
        await config_file_example()
        
        # Run batch jobs example (uncomment to test)
        # await batch_jobs_example()
        
        # Run monitoring example (uncomment to test)
        # await monitoring_example()
        
        logger.info("Examples completed successfully!")
        
    except Exception as e:
        logger.error(f"Example failed: {e}")


if __name__ == '__main__':
    asyncio.run(main())