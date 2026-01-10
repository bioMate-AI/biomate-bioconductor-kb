"""
Azure Batch executor implementation.
"""

import asyncio
import json
from typing import Dict, Any, Optional, List, Set
from datetime import datetime, timedelta

from azure.batch import BatchServiceClient
from azure.batch import models as batch_models
from azure.identity.aio import DefaultAzureCredential, ClientSecretCredential
from azure.core.exceptions import ResourceNotFoundError

from galaxy_cloud.core.executor import CloudExecutor
from galaxy_cloud.core.job import JobSpec, JobStatus, JobResult, JobEvent
from galaxy_cloud.registry import cloud_executor
from galaxy_cloud.providers.azure.auth import AzureAuth


@cloud_executor("azure-batch", {
    "description": "Azure Batch executor for container workloads",
    "supported_features": [
        "container_jobs", "spot_instances", "job_arrays", 
        "auto_scaling", "custom_images", "gpu_support"
    ],
    "version": "1.0.0"
})
class AzureBatchExecutor(CloudExecutor):
    """Azure Batch executor implementation."""
    
    def __init__(self, config: Dict[str, Any], **kwargs):
        super().__init__(config, **kwargs)
        
        # Azure Batch configuration
        self.account_name = config.get('batch_account')
        self.account_url = config.get('batch_url') or f"https://{self.account_name}.{config.get('region', 'eastus')}.batch.azure.com"
        self.pool_id = config.get('pool_id', 'galaxy-compute-pool')
        self.resource_group = config.get('resource_group')
        self.subscription_id = config.get('subscription_id')
        
        # Spot instance configuration
        self.enable_spot = config.get('enable_spot', False)
        self.spot_allocation_policy = config.get('spot_allocation_policy', 'lowpriority')
        
        # Auto-scaling configuration
        self.enable_autoscale = config.get('enable_autoscale', True)
        self.min_nodes = config.get('min_nodes', 0)
        self.max_nodes = config.get('max_nodes', 10)
        
        # Container registry
        self.container_registry_url = config.get('container_registry_url')
        self.container_registry_username = config.get('container_registry_username')
        self.container_registry_password = config.get('container_registry_password')
        
        # Internal state
        self.batch_client: Optional[BatchServiceClient] = None
        self.auth_provider: Optional[AzureAuth] = None
        self._job_definitions: Dict[str, str] = {}
        self._active_jobs: Set[str] = set()
        
    async def initialize(self) -> None:
        """Initialize Azure Batch client and authentication."""
        self.auth_provider = AzureAuth(self.config)
        await self.auth_provider.initialize()
        
        # Get Azure credentials
        credentials = await self.auth_provider.get_credentials()
        
        # Initialize Batch client
        self.batch_client = BatchServiceClient(
            credentials.raw_credentials,
            batch_url=self.account_url
        )
        
        # Ensure compute pool exists
        await self._ensure_compute_pool()
        
        self._initialized = True
        self.logger.info(f"Azure Batch executor initialized for account: {self.account_name}")
    
    async def cleanup(self) -> None:
        """Clean up Azure Batch resources."""
        if self.auth_provider:
            await self.auth_provider.cleanup()
        
        self._initialized = False
        self.logger.info("Azure Batch executor cleaned up")
    
    @property
    def provider_name(self) -> str:
        return "azure"
    
    @property
    def executor_type(self) -> str:
        return "batch"
    
    async def submit_job(self, job_spec: JobSpec) -> str:
        """Submit job to Azure Batch."""
        if not self._initialized:
            raise RuntimeError("Executor not initialized")
        
        try:
            # Prepare container configuration
            container_config = await self._prepare_container_config(job_spec)
            
            # Create job definition
            job_id = f"galaxy-{job_spec.job_id}-{int(datetime.utcnow().timestamp())}"
            
            # Handle job arrays if specified
            if job_spec.cloud_options.get('array_size'):
                return await self._submit_job_array(job_spec, job_id, container_config)
            else:
                return await self._submit_single_job(job_spec, job_id, container_config)
                
        except Exception as e:
            self.logger.error(f"Failed to submit job {job_spec.job_id}: {e}")
            raise
    
    async def _submit_single_job(self, job_spec: JobSpec, job_id: str, container_config: dict) -> str:
        """Submit a single job to Azure Batch."""
        
        # Create task configuration
        task_config = batch_models.TaskAddParameter(
            id=job_id,
            display_name=job_spec.name,
            command_line=self._build_command_line(job_spec),
            container_settings=batch_models.TaskContainerSettings(
                image_name=job_spec.container.image,
                container_run_options=self._build_container_options(job_spec),
                registry=container_config.get('registry')
            ),
            resource_files=await self._prepare_input_files(job_spec),
            output_files=await self._prepare_output_files(job_spec),
            constraints=batch_models.TaskConstraints(
                max_wall_clock_time=timedelta(seconds=job_spec.timeout_seconds) if job_spec.timeout_seconds else None,
                max_task_retry_count=job_spec.retry_attempts
            ),
            user_identity=batch_models.UserIdentity(
                auto_user=batch_models.AutoUserSpecification(
                    scope=batch_models.AutoUserScope.pool,
                    elevation_level=batch_models.ElevationLevel.admin if job_spec.container.privileged else batch_models.ElevationLevel.non_admin
                )
            ),
            environment_settings=[
                batch_models.EnvironmentSetting(name=k, value=v)
                for k, v in job_spec.container.env.items()
            ]
        )
        
        # Create job if it doesn't exist
        job_pool_id = await self._get_or_create_job(job_spec, job_id)
        
        # Add task to job
        await self._add_task_to_job(job_pool_id, task_config)
        
        self._active_jobs.add(job_id)
        self.logger.info(f"Submitted Azure Batch job: {job_id}")
        
        return job_id
    
    async def _submit_job_array(self, job_spec: JobSpec, job_id: str, container_config: dict) -> str:
        """Submit a job array to Azure Batch."""
        array_size = job_spec.cloud_options['array_size']
        
        tasks = []
        for i in range(array_size):
            task_id = f"{job_id}-{i}"
            
            # Update environment with array index
            env_vars = job_spec.container.env.copy()
            env_vars['AZURE_BATCH_TASK_INDEX'] = str(i)
            env_vars['AZURE_BATCH_JOB_ARRAY_INDEX'] = str(i)
            
            task_config = batch_models.TaskAddParameter(
                id=task_id,
                display_name=f"{job_spec.name} [{i}]",
                command_line=self._build_command_line(job_spec),
                container_settings=batch_models.TaskContainerSettings(
                    image_name=job_spec.container.image,
                    container_run_options=self._build_container_options(job_spec),
                    registry=container_config.get('registry')
                ),
                resource_files=await self._prepare_input_files(job_spec),
                output_files=await self._prepare_output_files(job_spec),
                constraints=batch_models.TaskConstraints(
                    max_wall_clock_time=timedelta(seconds=job_spec.timeout_seconds) if job_spec.timeout_seconds else None,
                    max_task_retry_count=job_spec.retry_attempts
                ),
                environment_settings=[
                    batch_models.EnvironmentSetting(name=k, value=v)
                    for k, v in env_vars.items()
                ]
            )
            tasks.append(task_config)
        
        # Create job and add all tasks
        job_pool_id = await self._get_or_create_job(job_spec, job_id)
        
        # Add tasks in batches
        batch_size = 100  # Azure Batch limit
        for i in range(0, len(tasks), batch_size):
            batch_tasks = tasks[i:i + batch_size]
            await asyncio.to_thread(
                self.batch_client.task.add_collection,
                job_id=job_pool_id,
                value=batch_tasks
            )
        
        self._active_jobs.add(job_id)
        self.logger.info(f"Submitted Azure Batch job array: {job_id} with {array_size} tasks")
        
        return job_id
    
    async def get_job_status(self, cloud_job_id: str) -> JobStatus:
        """Get job status from Azure Batch."""
        try:
            # For job arrays, check all tasks
            if '-' in cloud_job_id and cloud_job_id.count('-') > 2:
                # This is likely a job array task
                job_id = '-'.join(cloud_job_id.split('-')[:-1])
                return await self._get_job_array_status(job_id)
            else:
                return await self._get_single_job_status(cloud_job_id)
                
        except ResourceNotFoundError:
            return JobStatus.UNKNOWN
        except Exception as e:
            self.logger.error(f"Failed to get status for job {cloud_job_id}: {e}")
            return JobStatus.UNKNOWN
    
    async def _get_single_job_status(self, job_id: str) -> JobStatus:
        """Get status of a single job."""
        task = await asyncio.to_thread(
            self.batch_client.task.get,
            job_id=job_id,
            task_id=job_id
        )
        
        return self._map_azure_task_state_to_job_status(task.state)
    
    async def _get_job_array_status(self, job_id: str) -> JobStatus:
        """Get aggregated status of a job array."""
        tasks = await asyncio.to_thread(
            self.batch_client.task.list,
            job_id=job_id
        )
        
        task_states = [task.state for task in tasks]
        
        # Determine overall status
        if any(state == batch_models.TaskState.running for state in task_states):
            return JobStatus.RUNNING
        elif all(state == batch_models.TaskState.completed for state in task_states):
            return JobStatus.COMPLETED
        elif any(state == batch_models.TaskState.failed for state in task_states):
            return JobStatus.FAILED
        elif all(state in [batch_models.TaskState.active, batch_models.TaskState.preparing] for state in task_states):
            return JobStatus.QUEUED
        else:
            return JobStatus.PENDING
    
    async def get_job_result(self, cloud_job_id: str) -> JobResult:
        """Get detailed job result from Azure Batch."""
        try:
            # Get task details
            task = await asyncio.to_thread(
                self.batch_client.task.get,
                job_id=cloud_job_id,
                task_id=cloud_job_id
            )
            
            # Get execution info
            exec_info = task.execution_info
            
            # Get node info for resource usage
            node_info = None
            if exec_info and exec_info.node_info:
                try:
                    node = await asyncio.to_thread(
                        self.batch_client.compute_node.get,
                        pool_id=exec_info.node_info.pool_id,
                        node_id=exec_info.node_info.node_id
                    )
                    node_info = node
                except:
                    pass
            
            # Build result
            result = JobResult(
                job_id=cloud_job_id,
                cloud_job_id=cloud_job_id,
                status=self._map_azure_task_state_to_job_status(task.state),
                submitted_at=task.creation_time,
                started_at=exec_info.start_time if exec_info else None,
                finished_at=exec_info.end_time if exec_info else None,
                exit_code=exec_info.exit_code if exec_info else None,
                cloud_metadata={
                    'task_state': task.state.value if task.state else None,
                    'node_id': exec_info.node_info.node_id if exec_info and exec_info.node_info else None,
                    'pool_id': exec_info.node_info.pool_id if exec_info and exec_info.node_info else None,
                    'task_root_directory': exec_info.node_info.task_root_directory if exec_info and exec_info.node_info else None,
                    'vm_size': node_info.vm_size if node_info else None,
                    'task_slots': exec_info.node_info.task_root_directory_url if exec_info and exec_info.node_info else None
                }
            )
            
            # Get task failure info if failed
            if task.state == batch_models.TaskState.failed and exec_info and exec_info.failure_info:
                result.error_message = exec_info.failure_info.message
                result.error_details = {
                    'category': exec_info.failure_info.category.value if exec_info.failure_info.category else None,
                    'code': exec_info.failure_info.code,
                    'details': [detail.name + ': ' + detail.value for detail in exec_info.failure_info.details] if exec_info.failure_info.details else []
                }
            
            # Try to get stdout/stderr from output files
            try:
                stdout_content, stderr_content = await self._get_task_output(cloud_job_id, cloud_job_id)
                result.stdout = stdout_content
                result.stderr = stderr_content
            except:
                pass
            
            return result
            
        except Exception as e:
            self.logger.error(f"Failed to get job result for {cloud_job_id}: {e}")
            return JobResult(
                job_id=cloud_job_id,
                cloud_job_id=cloud_job_id,
                status=JobStatus.UNKNOWN,
                error_message=str(e)
            )
    
    async def cancel_job(self, cloud_job_id: str) -> bool:
        """Cancel job in Azure Batch."""
        try:
            await asyncio.to_thread(
                self.batch_client.task.terminate,
                job_id=cloud_job_id,
                task_id=cloud_job_id
            )
            
            self._active_jobs.discard(cloud_job_id)
            self.logger.info(f"Cancelled Azure Batch job: {cloud_job_id}")
            return True
            
        except Exception as e:
            self.logger.error(f"Failed to cancel job {cloud_job_id}: {e}")
            return False
    
    async def list_jobs(self, status_filter: Optional[JobStatus] = None) -> List[str]:
        """List jobs in Azure Batch."""
        try:
            jobs = await asyncio.to_thread(self.batch_client.job.list)
            job_ids = []
            
            for job in jobs:
                if status_filter:
                    job_status = self._map_azure_job_state_to_job_status(job.state)
                    if job_status == status_filter:
                        job_ids.append(job.id)
                else:
                    job_ids.append(job.id)
            
            return job_ids
            
        except Exception as e:
            self.logger.error(f"Failed to list jobs: {e}")
            return []
    
    # Helper methods
    
    def _map_azure_task_state_to_job_status(self, state: batch_models.TaskState) -> JobStatus:
        """Map Azure Batch task state to JobStatus."""
        mapping = {
            batch_models.TaskState.active: JobStatus.QUEUED,
            batch_models.TaskState.preparing: JobStatus.QUEUED,
            batch_models.TaskState.running: JobStatus.RUNNING,
            batch_models.TaskState.completed: JobStatus.COMPLETED,
            batch_models.TaskState.failed: JobStatus.FAILED,
        }
        return mapping.get(state, JobStatus.UNKNOWN)
    
    def _map_azure_job_state_to_job_status(self, state: batch_models.JobState) -> JobStatus:
        """Map Azure Batch job state to JobStatus."""
        mapping = {
            batch_models.JobState.active: JobStatus.RUNNING,
            batch_models.JobState.disabling: JobStatus.RUNNING,
            batch_models.JobState.disabled: JobStatus.CANCELLED,
            batch_models.JobState.enabling: JobStatus.QUEUED,
            batch_models.JobState.terminating: JobStatus.CANCELLED,
            batch_models.JobState.completed: JobStatus.COMPLETED,
            batch_models.JobState.deleting: JobStatus.CANCELLED,
        }
        return mapping.get(state, JobStatus.UNKNOWN)
    
    async def _ensure_compute_pool(self) -> None:
        """Ensure the compute pool exists and is properly configured."""
        try:
            pool = await asyncio.to_thread(
                self.batch_client.pool.get,
                pool_id=self.pool_id
            )
            self.logger.info(f"Using existing Azure Batch pool: {self.pool_id}")
            
        except ResourceNotFoundError:
            # Create new pool
            await self._create_compute_pool()
    
    async def _create_compute_pool(self) -> None:
        """Create a new compute pool."""
        self.logger.info(f"Creating Azure Batch pool: {self.pool_id}")
        
        # VM configuration for containers
        vm_config = batch_models.VirtualMachineConfiguration(
            image_reference=batch_models.ImageReference(
                publisher='microsoft-azure-batch',
                offer='ubuntu-server-container',
                sku='20-04-lts',
                version='latest'
            ),
            node_agent_sku_id='batch.node.ubuntu 20.04'
        )
        
        # Auto-scale formula
        autoscale_formula = f"""
        startingNumberOfVMs = {self.min_nodes};
        maxNumberofVMs = {self.max_nodes};
        pendingTaskSamplePercent = $PendingTasks.GetSamplePercent(180 * TimeInterval_Second);
        pendingTaskSamples = pendingTaskSamplePercent < 70 ? startingNumberOfVMs : avg($PendingTasks.GetSample(180 * TimeInterval_Second));
        $TargetDedicatedNodes = max(0, min(maxNumberofVMs, pendingTaskSamples));
        """
        
        if self.enable_spot:
            autoscale_formula += f"""
            $TargetLowPriorityNodes = max(0, min(maxNumberofVMs, pendingTaskSamples));
            $TargetDedicatedNodes = {self.min_nodes};
            """
        
        pool_config = batch_models.PoolAddParameter(
            id=self.pool_id,
            vm_size='Standard_D2s_v3',  # Default VM size
            virtual_machine_configuration=vm_config,
            enable_auto_scale=self.enable_autoscale,
            auto_scale_formula=autoscale_formula if self.enable_autoscale else None,
            target_dedicated_nodes=self.min_nodes if not self.enable_autoscale else None,
            target_low_priority_nodes=self.max_nodes if self.enable_spot and not self.enable_autoscale else None
        )
        
        await asyncio.to_thread(
            self.batch_client.pool.add,
            pool=pool_config
        )
        
        self.logger.info(f"Created Azure Batch pool: {self.pool_id}")
    
    async def _prepare_container_config(self, job_spec: JobSpec) -> dict:
        """Prepare container configuration."""
        config = {}
        
        if self.container_registry_url and job_spec.container.image.startswith(self.container_registry_url):
            config['registry'] = batch_models.ContainerRegistry(
                registry_server=self.container_registry_url,
                user_name=self.container_registry_username,
                password=self.container_registry_password
            )
        
        return config
    
    def _build_command_line(self, job_spec: JobSpec) -> str:
        """Build command line for container execution."""
        command_parts = []
        
        if job_spec.container.command:
            command_parts.extend(job_spec.container.command)
        
        if job_spec.container.args:
            command_parts.extend(job_spec.container.args)
        
        return ' '.join(f'"{part}"' if ' ' in part else part for part in command_parts)
    
    def _build_container_options(self, job_spec: JobSpec) -> str:
        """Build container run options."""
        options = []
        
        if job_spec.container.working_dir:
            options.append(f'--workdir "{job_spec.container.working_dir}"')
        
        if job_spec.container.privileged:
            options.append('--privileged')
        
        # Add resource constraints
        if job_spec.resources.memory_mb:
            options.append(f'--memory {job_spec.resources.memory_mb}m')
        
        if job_spec.resources.cpus:
            options.append(f'--cpus {job_spec.resources.cpus}')
        
        return ' '.join(options)
    
    async def _prepare_input_files(self, job_spec: JobSpec) -> List[batch_models.ResourceFile]:
        """Prepare input files for the job."""
        resource_files = []
        
        for local_path, container_path in job_spec.input_files.items():
            # Convert local path to Azure Blob URL
            blob_url = await self._upload_to_blob_storage(local_path)
            
            resource_files.append(batch_models.ResourceFile(
                http_url=blob_url,
                file_path=container_path
            ))
        
        return resource_files
    
    async def _prepare_output_files(self, job_spec: JobSpec) -> List[batch_models.OutputFile]:
        """Prepare output files for the job."""
        output_files = []
        
        for container_path, local_path in job_spec.output_files.items():
            # Create Azure Blob destination
            blob_destination = await self._create_blob_destination(local_path)
            
            output_files.append(batch_models.OutputFile(
                file_pattern=container_path,
                destination=blob_destination,
                upload_options=batch_models.OutputFileUploadOptions(
                    upload_condition=batch_models.OutputFileUploadCondition.task_completion
                )
            ))
        
        return output_files
    
    async def _get_or_create_job(self, job_spec: JobSpec, job_id: str) -> str:
        """Get or create a job for tasks."""
        try:
            job = await asyncio.to_thread(
                self.batch_client.job.get,
                job_id=job_id
            )
            return job.id
            
        except ResourceNotFoundError:
            # Create new job
            job_config = batch_models.JobAddParameter(
                id=job_id,
                display_name=job_spec.name,
                pool_info=batch_models.PoolInformation(pool_id=self.pool_id),
                priority=job_spec.priority,
                job_manager_task=None,
                job_preparation_task=None,
                job_release_task=None,
                common_environment_settings=[
                    batch_models.EnvironmentSetting(name=k, value=v)
                    for k, v in job_spec.labels.items()
                ]
            )
            
            await asyncio.to_thread(
                self.batch_client.job.add,
                job=job_config
            )
            
            return job_id
    
    async def _add_task_to_job(self, job_id: str, task_config: batch_models.TaskAddParameter) -> None:
        """Add a task to the job."""
        await asyncio.to_thread(
            self.batch_client.task.add,
            job_id=job_id,
            task=task_config
        )
    
    async def _upload_to_blob_storage(self, local_path: str) -> str:
        """Upload file to Azure Blob Storage and return URL."""
        # This would use Azure Blob Storage client
        # For now, return a placeholder
        return f"https://{self.account_name}.blob.core.windows.net/inputs/{local_path}"
    
    async def _create_blob_destination(self, local_path: str) -> batch_models.OutputFileBlobContainerDestination:
        """Create blob destination for output files."""
        return batch_models.OutputFileBlobContainerDestination(
            container_url=f"https://{self.account_name}.blob.core.windows.net/outputs/",
            path=local_path
        )
    
    async def _get_task_output(self, job_id: str, task_id: str) -> tuple[Optional[str], Optional[str]]:
        """Get task stdout and stderr."""
        try:
            # Get stdout
            stdout_stream = await asyncio.to_thread(
                self.batch_client.file.get_from_task,
                job_id=job_id,
                task_id=task_id,
                file_path='stdout.txt'
            )
            stdout_content = stdout_stream.content.decode('utf-8')
            
            # Get stderr
            stderr_stream = await asyncio.to_thread(
                self.batch_client.file.get_from_task,
                job_id=job_id,
                task_id=task_id,
                file_path='stderr.txt'
            )
            stderr_content = stderr_stream.content.decode('utf-8')
            
            return stdout_content, stderr_content
            
        except:
            return None, None