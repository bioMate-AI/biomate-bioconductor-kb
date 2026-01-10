"""
Command-line interface for Galaxy Cloud Executor.
"""

import asyncio
import logging
import sys
from pathlib import Path
from typing import Optional

import click
import yaml
from rich.console import Console
from rich.table import Table
from rich.json import JSON

from .config import CloudConfig, ConfigManager
from .factory import CloudExecutorFactory, CloudProviderFactory
from .core.job import JobSpec, JobStatus, ResourceSpec, ContainerSpec
from .registry import registry

console = Console()


@click.group()
@click.option('--config', '-c', type=click.Path(exists=True), help='Configuration file path')
@click.option('--log-level', default='INFO', help='Logging level', 
              type=click.Choice(['DEBUG', 'INFO', 'WARNING', 'ERROR']))
@click.pass_context
def cli(ctx, config, log_level):
    """Galaxy Cloud Executor CLI."""
    # Setup logging
    logging.basicConfig(
        level=getattr(logging, log_level),
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    
    # Store config path in context
    ctx.ensure_object(dict)
    ctx.obj['config_file'] = config


@cli.command()
@click.pass_context
def providers(ctx):
    """List available cloud providers."""
    config_file = ctx.obj.get('config_file')
    
    # Load configuration
    try:
        if config_file:
            config_manager = ConfigManager(config_file)
            cloud_config = config_manager.load_config()
        else:
            cloud_config = CloudConfig()
    except Exception as e:
        console.print(f"[red]Error loading configuration: {e}[/red]")
        sys.exit(1)
    
    # Get provider status
    provider_status = CloudProviderFactory.get_provider_status()
    enabled_providers = cloud_config.get_enabled_providers()
    
    # Create table
    table = Table(title="Cloud Provider Status")
    table.add_column("Provider", style="cyan")
    table.add_column("Enabled", style="green")
    table.add_column("Executor", style="blue")
    table.add_column("Storage", style="blue")
    table.add_column("Auth", style="blue")
    
    for provider, status in provider_status.items():
        enabled = "✓" if provider in enabled_providers else "✗"
        executor = "✓" if status['executor_available'] else "✗"
        storage = "✓" if status['storage_available'] else "✗"
        auth = "✓" if status['auth_available'] else "✗"
        
        table.add_row(provider, enabled, executor, storage, auth)
    
    console.print(table)


@cli.command()
@click.option('--provider', required=True, help='Cloud provider name')
@click.option('--job-spec', required=True, type=click.Path(exists=True), help='Job specification file')
@click.option('--wait', is_flag=True, help='Wait for job completion')
@click.pass_context
def submit(ctx, provider, job_spec, wait):
    """Submit a job to a cloud provider."""
    asyncio.run(_submit_job(ctx, provider, job_spec, wait))


async def _submit_job(ctx, provider, job_spec_file, wait_for_completion):
    """Submit job implementation."""
    config_file = ctx.obj.get('config_file')
    
    # Load configuration
    try:
        if config_file:
            config_manager = ConfigManager(config_file)
            cloud_config = config_manager.load_config()
        else:
            cloud_config = CloudConfig()
    except Exception as e:
        console.print(f"[red]Error loading configuration: {e}[/red]")
        return
    
    # Load job specification
    try:
        with open(job_spec_file) as f:
            job_data = yaml.safe_load(f)
        job_spec = JobSpec(**job_data)
    except Exception as e:
        console.print(f"[red]Error loading job specification: {e}[/red]")
        return
    
    # Create provider components
    try:
        components = CloudProviderFactory.create_from_config(provider, cloud_config)
        executor = components.get('executor')
        
        if not executor:
            console.print(f"[red]No executor available for provider {provider}[/red]")
            return
    except Exception as e:
        console.print(f"[red]Error creating provider components: {e}[/red]")
        return
    
    # Submit job
    try:
        async with executor:
            console.print(f"[green]Submitting job {job_spec.job_id} to {provider}...[/green]")
            cloud_job_id = await executor.submit_job(job_spec)
            console.print(f"[green]Job submitted with ID: {cloud_job_id}[/green]")
            
            if wait_for_completion:
                console.print("[yellow]Waiting for job completion...[/yellow]")
                result = await executor.wait_for_completion(cloud_job_id)
                
                console.print(f"[green]Job completed with status: {result.status}[/green]")
                if result.exit_code is not None:
                    console.print(f"Exit code: {result.exit_code}")
                if result.stdout:
                    console.print("STDOUT:")
                    console.print(result.stdout)
                if result.stderr:
                    console.print("STDERR:")
                    console.print(result.stderr)
    except Exception as e:
        console.print(f"[red]Error submitting job: {e}[/red]")


@cli.command()
@click.option('--provider', required=True, help='Cloud provider name')
@click.option('--job-id', required=True, help='Cloud job ID')
@click.pass_context
def status(ctx, provider, job_id):
    """Get job status."""
    asyncio.run(_get_job_status(ctx, provider, job_id))


async def _get_job_status(ctx, provider, job_id):
    """Get job status implementation."""
    config_file = ctx.obj.get('config_file')
    
    # Load configuration
    try:
        if config_file:
            config_manager = ConfigManager(config_file)
            cloud_config = config_manager.load_config()
        else:
            cloud_config = CloudConfig()
    except Exception as e:
        console.print(f"[red]Error loading configuration: {e}[/red]")
        return
    
    # Create executor
    try:
        components = CloudProviderFactory.create_from_config(provider, cloud_config)
        executor = components.get('executor')
        
        if not executor:
            console.print(f"[red]No executor available for provider {provider}[/red]")
            return
    except Exception as e:
        console.print(f"[red]Error creating executor: {e}[/red]")
        return
    
    # Get job status
    try:
        async with executor:
            status = await executor.get_job_status(job_id)
            result = await executor.get_job_result(job_id)
            
            table = Table(title=f"Job Status: {job_id}")
            table.add_column("Property", style="cyan")
            table.add_column("Value", style="green")
            
            table.add_row("Status", str(status))
            table.add_row("Submitted", str(result.submitted_at) if result.submitted_at else "N/A")
            table.add_row("Started", str(result.started_at) if result.started_at else "N/A")
            table.add_row("Finished", str(result.finished_at) if result.finished_at else "N/A")
            table.add_row("Exit Code", str(result.exit_code) if result.exit_code is not None else "N/A")
            
            console.print(table)
            
            if result.error_message:
                console.print(f"[red]Error: {result.error_message}[/red]")
    except Exception as e:
        console.print(f"[red]Error getting job status: {e}[/red]")


@cli.command()
@click.option('--provider', required=True, help='Cloud provider name')
@click.option('--job-id', required=True, help='Cloud job ID')
@click.pass_context
def logs(ctx, provider, job_id):
    """Get job logs."""
    asyncio.run(_get_job_logs(ctx, provider, job_id))


async def _get_job_logs(ctx, provider, job_id):
    """Get job logs implementation."""
    config_file = ctx.obj.get('config_file')
    
    # Load configuration
    try:
        if config_file:
            config_manager = ConfigManager(config_file)
            cloud_config = config_manager.load_config()
        else:
            cloud_config = CloudConfig()
    except Exception as e:
        console.print(f"[red]Error loading configuration: {e}[/red]")
        return
    
    # Create executor
    try:
        components = CloudProviderFactory.create_from_config(provider, cloud_config)
        executor = components.get('executor')
        
        if not executor:
            console.print(f"[red]No executor available for provider {provider}[/red]")
            return
    except Exception as e:
        console.print(f"[red]Error creating executor: {e}[/red]")
        return
    
    # Get job logs
    try:
        async with executor:
            result = await executor.get_job_result(job_id)
            
            if result.stdout:
                console.print("[bold blue]STDOUT:[/bold blue]")
                console.print(result.stdout)
            
            if result.stderr:
                console.print("[bold red]STDERR:[/bold red]")
                console.print(result.stderr)
            
            if not result.stdout and not result.stderr:
                console.print("[yellow]No logs available[/yellow]")
    except Exception as e:
        console.print(f"[red]Error getting job logs: {e}[/red]")


@cli.command()
@click.option('--output', '-o', type=click.Path(), help='Output file path')
def config_template(output):
    """Generate a configuration template."""
    template = {
        'aws': {
            'enabled': False,
            'region': 'us-east-1',
            'batch_queue': 'your-batch-queue',
            's3_bucket': 'your-s3-bucket',
            'resource_limits': {
                'max_cpus': 256,
                'max_memory_mb': 512000,
                'max_concurrent_jobs': 100
            }
        },
        'azure': {
            'enabled': False,
            'subscription_id': '${AZURE_SUBSCRIPTION_ID}',
            'batch_account': 'your-batch-account',
            'storage_account': 'your-storage-account'
        },
        'gcp': {
            'enabled': False,
            'project_id': '${GOOGLE_CLOUD_PROJECT}',
            'storage_bucket': 'your-gcs-bucket'
        },
        'kubernetes': {
            'enabled': False,
            'namespace': 'default',
            'storage_class': 'standard'
        },
        'default_provider': 'aws',
        'monitoring': {
            'log_level': 'info',
            'enable_metrics': True
        }
    }
    
    yaml_content = yaml.dump(template, default_flow_style=False, indent=2)
    
    if output:
        with open(output, 'w') as f:
            f.write(yaml_content)
        console.print(f"[green]Configuration template written to {output}[/green]")
    else:
        console.print(yaml_content)


@cli.command()
@click.option('--output', '-o', type=click.Path(), help='Output file path')
def job_template(output):
    """Generate a job specification template."""
    template = {
        'job_id': 'example-job-001',
        'name': 'Example Job',
        'container': {
            'image': 'ubuntu:20.04',
            'command': ['/bin/bash', '-c'],
            'args': ['echo "Hello, Cloud!"'],
            'env': {
                'EXAMPLE_VAR': 'example_value'
            },
            'working_dir': '/tmp'
        },
        'resources': {
            'cpus': 1,
            'memory_mb': 1024,
            'disk_gb': 10
        },
        'input_files': {},
        'output_files': {},
        'timeout_seconds': 3600,
        'retry_attempts': 3,
        'labels': {
            'project': 'galaxy-cloud-executor',
            'environment': 'test'
        }
    }
    
    yaml_content = yaml.dump(template, default_flow_style=False, indent=2)
    
    if output:
        with open(output, 'w') as f:
            f.write(yaml_content)
        console.print(f"[green]Job template written to {output}[/green]")
    else:
        console.print(yaml_content)


@cli.command()
@click.pass_context
def test_config(ctx):
    """Test configuration and provider availability."""
    config_file = ctx.obj.get('config_file')
    
    # Load configuration
    try:
        if config_file:
            config_manager = ConfigManager(config_file)
            cloud_config = config_manager.load_config()
            console.print(f"[green]Configuration loaded from {config_file}[/green]")
        else:
            cloud_config = CloudConfig()
            console.print("[yellow]Using default configuration[/yellow]")
    except Exception as e:
        console.print(f"[red]Error loading configuration: {e}[/red]")
        sys.exit(1)
    
    # Test each enabled provider
    enabled_providers = cloud_config.get_enabled_providers()
    
    if not enabled_providers:
        console.print("[yellow]No providers enabled in configuration[/yellow]")
        return
    
    async def test_providers():
        for provider in enabled_providers:
            console.print(f"\n[blue]Testing {provider} provider...[/blue]")
            
            try:
                components = CloudProviderFactory.create_from_config(provider, cloud_config)
                
                # Test authentication
                auth = components.get('auth')
                if auth:
                    async with auth:
                        auth_result = await auth.test_connection()
                        if auth_result['status'] == 'success':
                            console.print(f"[green]✓ Authentication successful[/green]")
                        else:
                            console.print(f"[red]✗ Authentication failed: {auth_result.get('error', 'Unknown error')}[/red]")
                
                # Test executor
                executor = components.get('executor')
                if executor:
                    async with executor:
                        health = await executor.health_check()
                        if health['status'] == 'healthy':
                            console.print(f"[green]✓ Executor healthy[/green]")
                        else:
                            console.print(f"[red]✗ Executor unhealthy: {health.get('error', 'Unknown error')}[/red]")
                
                # Test storage
                storage = components.get('storage')
                if storage:
                    async with storage:
                        console.print(f"[green]✓ Storage initialized[/green]")
                
            except Exception as e:
                console.print(f"[red]✗ Provider {provider} failed: {e}[/red]")
    
    asyncio.run(test_providers())


def main():
    """Main entry point."""
    cli()


if __name__ == '__main__':
    main()