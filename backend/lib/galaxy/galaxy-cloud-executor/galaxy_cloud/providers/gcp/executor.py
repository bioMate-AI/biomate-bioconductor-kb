"""
Google Cloud Batch executor implementation.
"""

import asyncio
import json
from typing import Dict, Any, Optional, List, Set
from datetime import datetime, timedelta

from google.cloud import batch_v1
from google.cloud.batch_v1 import types as batch_types
from google.api_core import exceptions as gcp_exceptions
from google.api_core import retry

from galaxy_cloud.core.executor import CloudExecutor
from galaxy_cloud.core.job import JobSpec, JobStatus, JobResult, JobEvent
from galaxy_cloud.registry import cloud_executor
from galaxy_cloud.providers.gcp.auth import GCPAuth


@cloud_executor("gcp-batch", {
    "description": "Google Cloud Batch executor for container workloads",
    "supported_features": [
        "container_jobs", "spot_instances", "job_arrays", 
        "preemptible_vms", "custom_machine_types", "gpu_support",
        "placement_groups", "network_isolation"
    ],
    "version": "1.0.0"
})
class GCPBatchExecutor(CloudExecutor):
    """Google Cloud Batch executor implementation."""
    
    def __init__(self, config: Dict[str, Any], **kwargs):
        super().__init__(config, **kwargs)
        
        # GCP configuration
        self.project_id = config.get('project_id')
        self.region = config.get('region', 'us-central1')
        self.zone = config.get('zone')  # Optional specific zone
        
        # Compute configuration
        self.machine_type = config.get('machine_type', 'e2-standard-2')
        self.disk_size_gb = config.get('disk_size_gb', 10)
        self.disk_type = config.get('disk_type', 'pd-standard')
        
        # Preemptible/Spot configuration
        self.use_spot = config.get('use_spot', False)
        self.use_preemptible = config.get('use_preemptible', False)
        
        # Network configuration
        self.network = config.get('network', 'default')
        self.subnet = config.get('subnet')
        self.no_external_ip = config.get('no_external_ip', False)
        
        # Service account
        self.service_account = config.get('service_account')
        self.service_account_scopes = config.get('service_account_scopes', [
            'https://www.googleapis.com/auth/cloud-platform'
        ])
        
        # Labels and metadata
        self.default_labels = config.get('labels', {})
        self.default_metadata = config.get('metadata', {})
        
        # GPU configuration
        self.gpu_type = config.get('gpu_type')
        self.gpu_count = config.get('gpu_count', 0)
        
        # Internal state
        self.batch_client: Optional[batch_v1.BatchServiceAsyncClient] = None
        self.auth_provider: Optional[GCPAuth] = None
        self._active_jobs: Set[str] = set()
        
    async def initialize(self) -> None:
        """Initialize Google Cloud Batch client and authentication."""
        self.auth_provider = GCPAuth(self.config)
        await self.auth_provider.initialize()
        
        # Get GCP credentials
        credentials = await self.auth_provider.get_credentials()
        
        # Initialize Batch client
        self.batch_client = batch_v1.BatchServiceAsyncClient(
            credentials=credentials.raw_credentials
        )
        
        self._initialized = True
        self.logger.info(f"GCP Batch executor initialized for project: {self.project_id}, region: {self.region}")
    
    async def cleanup(self) -> None:
        """Clean up GCP Batch resources."""
        if self.batch_client:
            await self.batch_client.transport.close()
            
        if self.auth_provider:
            await self.auth_provider.cleanup()
        
        self._initialized = False
        self.logger.info("GCP Batch executor cleaned up")
    
    @property
    def provider_name(self) -> str:
        return "gcp"
    
    @property
    def executor_type(self) -> str:
        return "batch"
    
    async def submit_job(self, job_spec: JobSpec) -> str:
        """Submit job to Google Cloud Batch."""
        if not self._initialized:
            raise RuntimeError("Executor not initialized")
        
        try:
            # Create job configuration
            job_config = await self._create_batch_job(job_spec)
            
            # Submit job
            job_name = f"galaxy-{job_spec.job_id}-{int(datetime.utcnow().timestamp())}"
            parent = f"projects/{self.project_id}/locations/{self.region}"
            
            request = batch_types.CreateJobRequest(
                parent=parent,
                job_id=job_name,
                job=job_config
            )
            
            operation = await self.batch_client.create_job(request=request)
            
            # Wait for operation to complete (job creation)
            job = await operation.result()
            
            self._active_jobs.add(job.name)
            self.logger.info(f"Submitted GCP Batch job: {job.name}")
            
            return job.name
            
        except Exception as e:
            self.logger.error(f"Failed to submit job {job_spec.job_id}: {e}")
            raise
    
    async def get_job_status(self, cloud_job_id: str) -> JobStatus:
        """Get job status from Google Cloud Batch."""
        try:
            request = batch_types.GetJobRequest(name=cloud_job_id)
            job = await self.batch_client.get_job(request=request)
            
            return self._map_gcp_job_state_to_job_status(job.status.state)
            
        except gcp_exceptions.NotFound:
            return JobStatus.UNKNOWN
        except Exception as e:
            self.logger.error(f"Failed to get status for job {cloud_job_id}: {e}")
            return JobStatus.UNKNOWN
    
    async def get_job_result(self, cloud_job_id: str) -> JobResult:
        """Get detailed job result from Google Cloud Batch."""
        try:
            request = batch_types.GetJobRequest(name=cloud_job_id)
            job = await self.batch_client.get_job(request=request)
            
            # Get task details
            task_groups = job.task_groups
            tasks_info = []
            
            if task_groups:
                # Get task execution details
                for task_group in task_groups:
                    parent = f"{cloud_job_id}/taskGroups/{task_group.name}"
                    list_request = batch_types.ListTasksRequest(parent=parent)
                    
                    tasks_response = await self.batch_client.list_tasks(request=list_request)
                    tasks_info.extend([task for task in tasks_response.tasks])
            
            # Calculate aggregated information
            total_tasks = len(tasks_info)
            completed_tasks = sum(1 for task in tasks_info if task.status.state == batch_types.TaskStatus.State.SUCCEEDED)
            failed_tasks = sum(1 for task in tasks_info if task.status.state == batch_types.TaskStatus.State.FAILED)
            
            # Get timing information
            submit_time = job.create_time
            start_time = None
            end_time = None
            
            if tasks_info:
                start_times = [task.status.events[0].event_time for task in tasks_info if task.status.events]
                if start_times:
                    start_time = min(start_times)
                
                end_times = [task.status.events[-1].event_time for task in tasks_info if task.status.events]
                if end_times:
                    end_time = max(end_times)
            
            # Build result
            result = JobResult(
                job_id=cloud_job_id,
                cloud_job_id=cloud_job_id,
                status=self._map_gcp_job_state_to_job_status(job.status.state),
                submitted_at=submit_time,
                started_at=start_time,
                finished_at=end_time,
                cloud_metadata={
                    'project_id': self.project_id,
                    'region': self.region,
                    'job_uid': job.uid,
                    'total_tasks': total_tasks,
                    'completed_tasks': completed_tasks,
                    'failed_tasks': failed_tasks,
                    'allocation_policy': self._get_allocation_policy_info(job),
                    'task_groups': len(task_groups) if task_groups else 0
                }
            )
            
            # Get error information if failed
            if job.status.state == batch_types.JobStatus.State.FAILED:
                failed_task_events = []
                for task in tasks_info:
                    if task.status.state == batch_types.TaskStatus.State.FAILED:
                        failed_task_events.extend([
                            event.description for event in task.status.events
                            if event.type_ == batch_types.TaskEvent.Type.TASK_FAILED
                        ])
                
                if failed_task_events:
                    result.error_message = "; ".join(failed_task_events[:3])  # First 3 errors
                    result.error_details = {
                        'failed_task_count': failed_tasks,
                        'error_messages': failed_task_events
                    }
            
            # Try to get stdout/stderr from completed tasks
            if tasks_info:
                first_task = tasks_info[0]
                try:
                    stdout_content, stderr_content = await self._get_task_logs(cloud_job_id, first_task.name)
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
        """Cancel job in Google Cloud Batch."""
        try:
            request = batch_types.DeleteJobRequest(name=cloud_job_id)
            operation = await self.batch_client.delete_job(request=request)
            
            # Wait for deletion to complete
            await operation.result()
            
            self._active_jobs.discard(cloud_job_id)
            self.logger.info(f"Cancelled GCP Batch job: {cloud_job_id}")
            return True
            
        except Exception as e:
            self.logger.error(f"Failed to cancel job {cloud_job_id}: {e}")
            return False
    
    async def list_jobs(self, status_filter: Optional[JobStatus] = None) -> List[str]:
        """List jobs in Google Cloud Batch."""
        try:
            parent = f"projects/{self.project_id}/locations/{self.region}"
            request = batch_types.ListJobsRequest(parent=parent)
            
            jobs_response = await self.batch_client.list_jobs(request=request)
            job_names = []
            
            for job in jobs_response.jobs:
                if status_filter:
                    job_status = self._map_gcp_job_state_to_job_status(job.status.state)
                    if job_status == status_filter:
                        job_names.append(job.name)
                else:
                    job_names.append(job.name)
            
            return job_names
            
        except Exception as e:
            self.logger.error(f"Failed to list jobs: {e}")
            return []
    
    # Helper methods
    
    def _map_gcp_job_state_to_job_status(self, state: batch_types.JobStatus.State) -> JobStatus:
        """Map GCP Batch job state to JobStatus."""
        mapping = {
            batch_types.JobStatus.State.STATE_UNSPECIFIED: JobStatus.UNKNOWN,
            batch_types.JobStatus.State.QUEUED: JobStatus.QUEUED,
            batch_types.JobStatus.State.SCHEDULED: JobStatus.QUEUED,
            batch_types.JobStatus.State.RUNNING: JobStatus.RUNNING,
            batch_types.JobStatus.State.SUCCEEDED: JobStatus.COMPLETED,
            batch_types.JobStatus.State.FAILED: JobStatus.FAILED,
            batch_types.JobStatus.State.DELETION_IN_PROGRESS: JobStatus.CANCELLED,
        }
        return mapping.get(state, JobStatus.UNKNOWN)
    
    async def _create_batch_job(self, job_spec: JobSpec) -> batch_types.Job:
        """Create Google Cloud Batch job configuration."""
        
        # Create runnable (container execution)
        container = batch_types.Runnable.Container(
            image_uri=job_spec.container.image,
            commands=job_spec.container.command or [],
            entrypoint=job_spec.container.args[0] if job_spec.container.args else None,
            options=self._build_container_options(job_spec)
        )
        
        runnable = batch_types.Runnable(container=container)
        
        # Set environment variables
        if job_spec.container.env:
            runnable.environment = batch_types.Environment(
                variables=job_spec.container.env
            )
        
        # Create task spec
        task_spec = batch_types.TaskSpec(
            runnables=[runnable],
            compute_resource=self._create_compute_resource(job_spec),
            max_retry_count=job_spec.retry_attempts,
            max_run_duration=self._create_duration(job_spec.timeout_seconds) if job_spec.timeout_seconds else None
        )
        
        # Handle job arrays
        array_size = job_spec.cloud_options.get('array_size', 1)
        task_count = array_size
        parallelism = min(array_size, job_spec.cloud_options.get('max_parallel_tasks', array_size))
        
        # Create task group
        task_group = batch_types.TaskGroup(
            task_spec=task_spec,
            task_count=task_count,
            parallelism=parallelism
        )
        
        # Create allocation policy
        allocation_policy = self._create_allocation_policy(job_spec)
        
        # Create job
        job = batch_types.Job(
            task_groups=[task_group],
            allocation_policy=allocation_policy,
            labels=self._merge_labels(job_spec.labels),
            logs_policy=batch_types.LogsPolicy(
                destination=batch_types.LogsPolicy.Destination.CLOUD_LOGGING
            )
        )
        
        return job
    
    def _create_compute_resource(self, job_spec: JobSpec) -> batch_types.ComputeResource:
        """Create compute resource specification."""
        resource = batch_types.ComputeResource(
            cpu_milli=int(job_spec.resources.cpus * 1000),
            memory_mib=job_spec.resources.memory_mb
        )
        
        # Add GPU support if specified
        if job_spec.resources.gpu and job_spec.resources.gpu > 0:
            resource.gpu_count = job_spec.resources.gpu
            
        return resource
    
    def _create_allocation_policy(self, job_spec: JobSpec) -> batch_types.AllocationPolicy:
        """Create allocation policy for the job."""
        
        # Create instance policy
        instance_policy = batch_types.AllocationPolicy.InstancePolicy(
            machine_type=self.machine_type,
            min_cpu_platform=job_spec.cloud_options.get('min_cpu_platform')
        )
        
        # Configure preemptible/spot instances
        if self.use_spot or self.use_preemptible:
            instance_policy.provisioning_model = batch_types.AllocationPolicy.ProvisioningModel.SPOT
        else:
            instance_policy.provisioning_model = batch_types.AllocationPolicy.ProvisioningModel.STANDARD
        
        # Configure boot disk
        disk = batch_types.AllocationPolicy.Disk(
            type_=self.disk_type,
            size_gb=self.disk_size_gb
        )
        instance_policy.boot_disk = batch_types.AllocationPolicy.AttachedDisk(
            new_disk=disk,
            device_name="boot"
        )
        
        # Configure additional disks if specified
        if job_spec.resources.disk_gb:
            data_disk = batch_types.AllocationPolicy.Disk(
                type_=self.disk_type,
                size_gb=job_spec.resources.disk_gb
            )
            instance_policy.disks.append(
                batch_types.AllocationPolicy.AttachedDisk(
                    new_disk=data_disk,
                    device_name="data"
                )
            )
        
        # Create instance policy template
        instance_template = batch_types.AllocationPolicy.InstancePolicyOrTemplate(
            policy=instance_policy
        )
        
        # Create location policy
        location_policy = batch_types.AllocationPolicy.LocationPolicy()
        if self.zone:
            location_policy.allowed_locations = [f"zones/{self.zone}"]
        
        # Create network policy
        network_interface = batch_types.AllocationPolicy.NetworkInterface(
            network=f"projects/{self.project_id}/global/networks/{self.network}"
        )
        
        if self.subnet:
            network_interface.subnetwork = f"projects/{self.project_id}/regions/{self.region}/subnetworks/{self.subnet}"
        
        if self.no_external_ip:
            network_interface.no_external_ip_address = True
        
        network_policy = batch_types.AllocationPolicy.NetworkPolicy(
            network_interfaces=[network_interface]
        )
        
        # Create service account
        service_account = None
        if self.service_account:
            service_account = batch_types.ServiceAccount(
                email=self.service_account,
                scopes=self.service_account_scopes
            )
        
        # Create allocation policy
        allocation_policy = batch_types.AllocationPolicy(
            instances=[instance_template],
            location=location_policy,
            network=network_policy,
            service_account=service_account
        )
        
        return allocation_policy
    
    def _build_container_options(self, job_spec: JobSpec) -> str:
        """Build container options string."""
        options = []
        
        if job_spec.container.working_dir:
            options.append(f'--workdir="{job_spec.container.working_dir}"')
        
        if job_spec.container.privileged:
            options.append('--privileged')
        
        # Add resource limits (handled by compute resource, but can add constraints)
        if job_spec.resources.memory_mb:
            options.append(f'--memory={job_spec.resources.memory_mb}m')
        
        if job_spec.resources.cpus:
            options.append(f'--cpus={job_spec.resources.cpus}')
        
        return ' '.join(options)
    
    def _create_duration(self, seconds: int) -> 'google.protobuf.duration_pb2.Duration':
        """Create protobuf Duration from seconds."""
        from google.protobuf import duration_pb2
        
        duration = duration_pb2.Duration()
        duration.FromSeconds(seconds)
        return duration
    
    def _merge_labels(self, job_labels: Dict[str, str]) -> Dict[str, str]:
        """Merge job labels with default labels."""
        labels = self.default_labels.copy()
        labels.update(job_labels)
        
        # Add system labels
        labels.update({
            'created-by': 'galaxy-cloud-executor',
            'provider': 'gcp-batch'
        })
        
        return labels
    
    def _get_allocation_policy_info(self, job: batch_types.Job) -> Dict[str, Any]:
        """Extract allocation policy information."""
        if not job.allocation_policy:
            return {}
        
        policy = job.allocation_policy
        info = {}
        
        if policy.instances:
            instance = policy.instances[0]
            if instance.policy:
                info['machine_type'] = instance.policy.machine_type
                info['provisioning_model'] = instance.policy.provisioning_model.name
                if instance.policy.boot_disk:
                    info['boot_disk_size_gb'] = instance.policy.boot_disk.new_disk.size_gb
                    info['boot_disk_type'] = instance.policy.boot_disk.new_disk.type_
        
        if policy.location and policy.location.allowed_locations:
            info['zones'] = policy.location.allowed_locations
        
        if policy.network and policy.network.network_interfaces:
            network_interface = policy.network.network_interfaces[0]
            info['network'] = network_interface.network
            if network_interface.subnetwork:
                info['subnet'] = network_interface.subnetwork
            info['no_external_ip'] = network_interface.no_external_ip_address
        
        if policy.service_account:
            info['service_account'] = policy.service_account.email
        
        return info
    
    async def _get_task_logs(self, job_name: str, task_name: str) -> tuple[Optional[str], Optional[str]]:
        """Get task logs from Cloud Logging."""
        try:
            # This would require Cloud Logging client integration
            # For now, return None - logs would be available in Cloud Logging
            # with the job name and task name as filters
            
            # Placeholder implementation
            return None, None
            
        except Exception as e:
            self.logger.warning(f"Failed to get logs for task {task_name}: {e}")
            return None, None
    
    async def get_job_logs(self, cloud_job_id: str) -> Dict[str, str]:
        """Get job logs for all tasks."""
        try:
            request = batch_types.GetJobRequest(name=cloud_job_id)
            job = await self.batch_client.get_job(request=request)
            
            logs = {}
            
            # Get logs for each task group
            for task_group in job.task_groups:
                parent = f"{cloud_job_id}/taskGroups/{task_group.name}"
                list_request = batch_types.ListTasksRequest(parent=parent)
                
                tasks_response = await self.batch_client.list_tasks(request=list_request)
                
                for task in tasks_response.tasks:
                    stdout, stderr = await self._get_task_logs(cloud_job_id, task.name)
                    logs[task.name] = {
                        'stdout': stdout,
                        'stderr': stderr
                    }
            
            return logs
            
        except Exception as e:
            self.logger.error(f"Failed to get job logs for {cloud_job_id}: {e}")
            return {}
    
    async def get_job_events(self, cloud_job_id: str) -> List[JobEvent]:
        """Get job events from Google Cloud Batch."""
        try:
            request = batch_types.GetJobRequest(name=cloud_job_id)
            job = await self.batch_client.get_job(request=request)
            
            events = []
            
            # Get events from all tasks
            for task_group in job.task_groups:
                parent = f"{cloud_job_id}/taskGroups/{task_group.name}"
                list_request = batch_types.ListTasksRequest(parent=parent)
                
                tasks_response = await self.batch_client.list_tasks(request=list_request)
                
                for task in tasks_response.tasks:
                    for event in task.status.events:
                        job_event = JobEvent(
                            job_id=cloud_job_id,
                            event_type=event.type_.name.lower(),
                            message=event.description,
                            timestamp=event.event_time,
                            details={
                                'task_name': task.name,
                                'task_index': task.task_index,
                                'event_type': event.type_.name
                            }
                        )
                        events.append(job_event)
            
            # Sort events by timestamp
            events.sort(key=lambda e: e.timestamp)
            
            return events
            
        except Exception as e:
            self.logger.error(f"Failed to get job events for {cloud_job_id}: {e}")
            return []