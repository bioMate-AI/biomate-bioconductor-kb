#!/usr/bin/env python3
"""
Complete multi-cloud workflow example demonstrating all cloud providers.
"""

import asyncio
import logging
from pathlib import Path

from galaxy_cloud import CloudExecutorFactory, CloudStorageFactory
from galaxy_cloud.config import load_config
from galaxy_cloud.core.job import JobSpec, ResourceSpec, ContainerSpec


async def main():
    """Demonstrate multi-cloud workflow execution."""
    
    # Setup logging
    logging.basicConfig(level=logging.INFO)
    logger = logging.getLogger(__name__)
    
    # Load configuration
    config = load_config('examples/complete_cloud_config.yaml')
    
    logger.info("=== Galaxy Cloud Executor Multi-Cloud Demo ===")
    logger.info(f"Enabled providers: {config.get_enabled_providers()}")
    
    # Test each enabled provider
    providers_to_test = []
    
    if config.aws.enabled:
        providers_to_test.append(('aws-batch', config.aws.dict()))
    
    if config.azure.enabled:
        providers_to_test.append(('azure-batch', config.azure.dict()))
    
    if config.gcp.enabled:
        providers_to_test.append(('gcp-batch', config.gcp.dict()))
    
    if config.kubernetes.enabled:
        providers_to_test.append(('kubernetes', config.kubernetes.dict()))
    
    # Run workflow on each provider
    for provider_name, provider_config in providers_to_test:
        await run_provider_workflow(provider_name, provider_config, logger)
    
    # Demonstrate cross-cloud storage operations
    await demonstrate_storage_operations(config, logger)
    
    logger.info("=== Multi-cloud demo completed ===")


async def run_provider_workflow(provider_name: str, provider_config: dict, logger):
    """Run a sample workflow on a specific provider."""
    
    logger.info(f"\n--- Testing {provider_name} ---")
    
    try:
        # Create executor
        executor = CloudExecutorFactory.create(provider_name, provider_config)
        
        # Define a simple bioinformatics job
        job_spec = JobSpec(
            job_id=f"demo-{provider_name.replace('-', '_')}-001",
            name=f"Multi-cloud Demo on {provider_name}",
            container=ContainerSpec(
                image="biocontainers/fastqc:v0.11.9_cv8",
                command=["fastqc"],
                args=["--version"],
                env={
                    "PROVIDER": provider_name,
                    "DEMO_MODE": "true"
                }
            ),
            resources=ResourceSpec(
                cpus=1,
                memory_mb=2048
            ),
            timeout_seconds=300,
            retry_attempts=2,
            labels={
                "demo": "multi-cloud",
                "provider": provider_name,
                "tool": "fastqc"
            }
        )
        
        # Execute workflow
        async with executor:
            logger.info(f"Submitting job to {provider_name}...")
            cloud_job_id = await executor.submit_job(job_spec)
            logger.info(f"Job submitted: {cloud_job_id}")
            
            # Monitor job
            logger.info("Monitoring job progress...")
            result = await executor.wait_for_completion(cloud_job_id, timeout=600)
            
            logger.info(f"Job completed with status: {result.status}")
            if result.stdout:
                logger.info(f"Output: {result.stdout[:200]}...")
            
            if result.error_message:
                logger.warning(f"Error: {result.error_message}")
            
            # Print resource usage if available
            if result.cloud_metadata:
                logger.info(f"Metadata: {result.cloud_metadata}")
    
    except Exception as e:
        logger.error(f"Failed to run workflow on {provider_name}: {e}")


async def demonstrate_storage_operations(config, logger):
    """Demonstrate cross-cloud storage operations."""
    
    logger.info("\n--- Storage Operations Demo ---")
    
    # Test storage providers
    storage_providers = []
    
    if config.aws.enabled and config.aws.s3_bucket:
        storage_providers.append(('s3', {
            'bucket_name': config.aws.s3_bucket,
            'region': config.aws.region
        }))
    
    if config.azure.enabled and config.azure.storage_account:
        storage_providers.append(('azblob', {
            'storage_account': config.azure.storage_account,
            'container_name': config.azure.storage_container
        }))
    
    if config.gcp.enabled and config.gcp.storage_bucket:
        storage_providers.append(('gcs', {
            'project_id': config.gcp.project_id,
            'bucket_name': config.gcp.storage_bucket
        }))
    
    if config.kubernetes.enabled:
        storage_providers.append(('k8s-pv', {
            'namespace': config.kubernetes.namespace,
            'storage_class': config.kubernetes.storage_class
        }))
    
    # Create test data
    test_data = b"Hello from Galaxy Cloud Executor!\nThis is a multi-cloud storage test.\n"
    
    for storage_name, storage_config in storage_providers:
        try:
            logger.info(f"Testing {storage_name} storage...")
            
            storage = CloudStorageFactory.create(storage_name, storage_config)
            
            async with storage:
                # Test file operations
                test_uri = f"{storage.scheme}://test-bucket/demo/test-file.txt"
                
                # Upload test data
                await storage.write_bytes(test_uri, test_data)
                logger.info(f"Uploaded test data to {test_uri}")
                
                # Download and verify
                downloaded_data = await storage.read_bytes(test_uri)
                assert downloaded_data == test_data
                logger.info(f"Downloaded and verified data from {test_uri}")
                
                # List files
                files = []
                async for file_uri in storage.list_files(f"{storage.scheme}://test-bucket/demo/"):
                    files.append(file_uri)
                
                logger.info(f"Found {len(files)} files in demo directory")
                
                # Clean up
                await storage.delete(test_uri)
                logger.info(f"Cleaned up test file: {test_uri}")
        
        except Exception as e:
            logger.error(f"Storage test failed for {storage_name}: {e}")


async def run_bioinformatics_pipeline(config, logger):
    """Run a complete bioinformatics pipeline across multiple clouds."""
    
    logger.info("\n--- Bioinformatics Pipeline Demo ---")
    
    # Pipeline stages
    stages = [
        {
            "name": "Quality Control",
            "tool": "fastqc",
            "image": "biocontainers/fastqc:v0.11.9_cv8",
            "command": ["fastqc"],
            "args": ["--extract", "/input/sample.fastq", "-o", "/output/"],
            "resources": ResourceSpec(cpus=2, memory_mb=4096),
            "timeout": 600
        },
        {
            "name": "Read Trimming", 
            "tool": "trimmomatic",
            "image": "biocontainers/trimmomatic:v0.39_cv1",
            "command": ["trimmomatic"],
            "args": ["SE", "/input/sample.fastq", "/output/trimmed.fastq", "TRAILING:20", "MINLEN:50"],
            "resources": ResourceSpec(cpus=4, memory_mb=8192),
            "timeout": 1200
        },
        {
            "name": "Sequence Alignment",
            "tool": "bwa",
            "image": "biocontainers/bwa:v0.7.17_cv1",
            "command": ["bwa"],
            "args": ["mem", "/reference/genome.fa", "/input/trimmed.fastq"],
            "resources": ResourceSpec(cpus=8, memory_mb=16384),
            "timeout": 3600
        },
        {
            "name": "Variant Calling",
            "tool": "bcftools",
            "image": "biocontainers/bcftools:v1.9_cv1",
            "command": ["bcftools"],
            "args": ["call", "-mv", "/input/aligned.bam"],
            "resources": ResourceSpec(cpus=4, memory_mb=8192),
            "timeout": 1800
        }
    ]
    
    # Run pipeline across different cloud providers
    providers = config.get_enabled_providers()
    
    for i, stage in enumerate(stages):
        # Round-robin across providers
        provider = providers[i % len(providers)]
        provider_config = config.get_provider_config(provider).dict()
        
        logger.info(f"Running '{stage['name']}' on {provider}...")
        
        # Map provider to executor type
        executor_type_map = {
            'aws': 'aws-batch',
            'azure': 'azure-batch', 
            'gcp': 'gcp-batch',
            'kubernetes': 'kubernetes'
        }
        
        executor_type = executor_type_map[provider]
        executor = CloudExecutorFactory.create(executor_type, provider_config)
        
        job_spec = JobSpec(
            job_id=f"pipeline-{stage['tool']}-{i+1:03d}",
            name=f"Pipeline Stage: {stage['name']}",
            container=ContainerSpec(
                image=stage['image'],
                command=stage['command'],
                args=stage['args'],
                env={
                    "STAGE": stage['name'],
                    "PIPELINE_ID": "bioinformatics-demo",
                    "PROVIDER": provider
                }
            ),
            resources=stage['resources'],
            timeout_seconds=stage['timeout'],
            retry_attempts=2,
            labels={
                "pipeline": "bioinformatics",
                "stage": stage['tool'],
                "provider": provider
            }
        )
        
        try:
            async with executor:
                cloud_job_id = await executor.submit_job(job_spec)
                logger.info(f"Stage '{stage['name']}' submitted: {cloud_job_id}")
                
                result = await executor.wait_for_completion(cloud_job_id, timeout=stage['timeout'] + 300)
                logger.info(f"Stage '{stage['name']}' completed with status: {result.status}")
                
                if result.status.value != 'completed':
                    logger.error(f"Pipeline failed at stage '{stage['name']}'")
                    break
        
        except Exception as e:
            logger.error(f"Failed to run stage '{stage['name']}': {e}")
            break
    
    logger.info("Bioinformatics pipeline completed")


async def demonstrate_job_arrays(config, logger):
    """Demonstrate parallel job array execution."""
    
    logger.info("\n--- Job Arrays Demo ---")
    
    # Use default provider for job arrays
    default_provider = config.default_provider or config.get_enabled_providers()[0]
    provider_config = config.get_provider_config(default_provider).dict()
    
    executor_type_map = {
        'aws': 'aws-batch',
        'azure': 'azure-batch',
        'gcp': 'gcp-batch', 
        'kubernetes': 'kubernetes'
    }
    
    executor_type = executor_type_map[default_provider]
    executor = CloudExecutorFactory.create(executor_type, provider_config)
    
    # Parameter sweep job array
    job_spec = JobSpec(
        job_id="parameter-sweep-array",
        name="Parameter Sweep Analysis",
        container=ContainerSpec(
            image="python:3.9-slim",
            command=["python"],
            args=["-c", """
import os
import time
import random

# Get array index
array_index = int(os.environ.get('JOB_COMPLETION_INDEX', 
                                 os.environ.get('AWS_BATCH_JOB_ARRAY_INDEX',
                                 os.environ.get('AZURE_BATCH_TASK_INDEX', '0'))))

# Simulate parameter sweep
parameter = 0.1 + (array_index * 0.1)
print(f"Running analysis with parameter={parameter:.2f}")

# Simulate computation
time.sleep(random.uniform(10, 30))

# Simulate result
result = parameter * random.uniform(0.8, 1.2)
print(f"Result: {result:.4f}")
print(f"Task {array_index} completed successfully")
            """],
            env={
                "PARAMETER_SWEEP": "true",
                "ANALYSIS_TYPE": "demo"
            }
        ),
        resources=ResourceSpec(
            cpus=1,
            memory_mb=1024
        ),
        timeout_seconds=300,
        cloud_options={
            'array_size': 10,
            'max_parallel_tasks': 5
        },
        labels={
            "job_type": "array",
            "analysis": "parameter_sweep"
        }
    )
    
    try:
        async with executor:
            logger.info(f"Submitting job array to {default_provider}...")
            cloud_job_id = await executor.submit_job(job_spec)
            logger.info(f"Job array submitted: {cloud_job_id}")
            
            # Monitor array job
            result = await executor.wait_for_completion(cloud_job_id, timeout=900)
            logger.info(f"Job array completed with status: {result.status}")
            
            if result.cloud_metadata:
                logger.info(f"Array metadata: {result.cloud_metadata}")
    
    except Exception as e:
        logger.error(f"Job array execution failed: {e}")


if __name__ == "__main__":
    asyncio.run(main())