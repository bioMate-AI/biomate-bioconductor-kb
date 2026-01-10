"""
AWS Batch executor implementation.
Inspired by Nextflow's AwsBatchExecutor.
"""

import asyncio
import logging
import json
from typing import Dict, Any, Optional, List
from datetime import datetime, timedelta

try:
    import boto3
    from botocore.exceptions import ClientError
    BOTO3_AVAILABLE = True
except ImportError:
    BOTO3_AVAILABLE = False

from tenacity import retry, stop_after_attempt, wait_exponential, retry_if_exception_type

from ...core.executor import CloudExecutor
from ...core.job import JobSpec, JobStatus, JobResult, ResourceSpec
from ...core.auth import CloudAuth
from ...registry import cloud_executor
from .auth import AWSAuth

logger = logging.getLogger(__name__)


@cloud_executor("aws-batch", metadata={
    "requires": ["boto3"], 
    "description": "AWS Batch executor for scalable job processing",
    "supports_arrays": True,
    "supports_spot": True
})
class AWSBatchExecutor(CloudExecutor):
    """
    AWS Batch executor implementation.
    
    Features:
    - AWS Batch job submission and monitoring
    - Spot instance support with intelligent retry
    - Job arrays for parallel processing
    - CloudWatch logs integration
    - ECS task monitoring
    """
    
    def __init__(self, config: Dict[str, Any], auth: Optional[CloudAuth] = None):
        """
        Initialize AWS Batch executor.
        
        Args:
            config: AWS Batch configuration
            auth: Optional AWS authentication instance
        """
        super().__init__(config)
        
        if not BOTO3_AVAILABLE:
            raise ImportError("boto3 is required for AWS Batch executor. Install with: pip install boto3")
        
        self.auth = auth or AWSAuth(config)
        
        # AWS Batch configuration
        self.region = config.get('region', 'us-east-1')
        self.job_queue = config.get('batch_queue') or config.get('job_queue')
        self.job_definition_name = config.get('batch_job_definition', 'galaxy-cloud-executor')
        self.compute_environment = config.get('batch_compute_environment')
        
        # Spot instance configuration
        self.spot_allocation = config.get('spot_allocation', 'onDemand')
        self.max_spot_attempts = config.get('max_spot_attempts', 3)
        
        # S3 configuration for job data
        self.s3_bucket = config.get('s3_bucket')
        self.s3_prefix = config.get('s3_prefix', 'galaxy-cloud-executor')
        
        # Resource limits
        self.resource_limits = config.get('resource_limits', {})
        
        # AWS clients
        self._batch_client = None
        self._ecs_client = None
        self._logs_client = None
        self._s3_client = None
        
        # Job tracking
        self._job_definitions: Dict[str, str] = {}
        self._job_arns: Dict[str, str] = {}
    
    async def initialize(self) -> None:
        """Initialize the AWS Batch executor."""
        # Initialize authentication
        if isinstance(self.auth, AWSAuth):
            await self.auth.initialize()
        
        # Create AWS clients
        self._batch_client = await self.auth.get_boto3_client('batch', region_name=self.region)
        self._ecs_client = await self.auth.get_boto3_client('ecs', region_name=self.region)
        self._logs_client = await self.auth.get_boto3_client('logs', region_name=self.region)
        
        if self.s3_bucket:
            self._s3_client = await self.auth.get_boto3_client('s3', region_name=self.region)
        
        # Validate job queue exists
        await self._validate_job_queue()
        
        self._initialized = True
        logger.info(f"Initialized AWS Batch executor for region {self.region}")
    
    async def cleanup(self) -> None:
        """Clean up the executor."""
        self._batch_client = None
        self._ecs_client = None
        self._logs_client = None
        self._s3_client = None
        
        if self.auth:
            await self.auth.cleanup()
        
        self._initialized = False
    
    @property
    def provider_name(self) -> str:
        """Return the provider name."""
        return "aws"
    
    @property
    def executor_type(self) -> str:
        """Return the executor type."""
        return "batch"
    
    async def _validate_job_queue(self) -> None:
        """Validate that the job queue exists and is active."""
        if not self.job_queue:
            raise ValueError("AWS Batch job queue not specified in configuration")
        
        def _check_queue():
            response = self._batch_client.describe_job_queues(jobQueues=[self.job_queue])
            queues = response.get('jobQueues', [])
            
            if not queues:
                raise ValueError(f"Job queue '{self.job_queue}' not found")
            
            queue = queues[0]
            if queue['state'] != 'ENABLED':
                raise ValueError(f"Job queue '{self.job_queue}' is not enabled (state: {queue['state']})")
            
            return queue
        
        loop = asyncio.get_event_loop()
        await loop.run_in_executor(None, _check_queue)
    
    @retry(
        stop=stop_after_attempt(3),
        wait=wait_exponential(multiplier=1, min=4, max=60),
        retry=retry_if_exception_type(ClientError)
    )
    async def submit_job(self, job_spec: JobSpec) -> str:
        """
        Submit a job to AWS Batch.
        
        Args:
            job_spec: Complete job specification
            
        Returns:
            AWS Batch job ID
        """
        self._ensure_initialized()
        self.validate_job_spec(job_spec)
        
        # Create job definition if needed
        job_def_arn = await self._ensure_job_definition(job_spec)
        
        # Upload input files to S3 if configured
        if self._s3_client and job_spec.input_files:
            await self._upload_input_files(job_spec)
        
        # Build job submission request
        submit_request = await self._build_submit_request(job_spec, job_def_arn)
        
        # Submit job
        def _submit():
            try:
                response = self._batch_client.submit_job(**submit_request)
                return response['jobId']
            except Exception as e:
                self.logger.error(f"AWS Batch submit_job failed: {e}")
                self.logger.error(f"Submit request: {submit_request}")
                raise

        loop = asyncio.get_event_loop()
        job_id = await loop.run_in_executor(None, _submit)
        
        # Store job metadata
        self._job_arns[job_id] = job_def_arn
        
        logger.info(f"Submitted job {job_spec.job_id} to AWS Batch with ID {job_id}")
        return job_id
    
    async def _ensure_job_definition(self, job_spec: JobSpec) -> str:
        """
        Ensure job definition exists, creating it if necessary.
        
        Args:
            job_spec: Job specification
            
        Returns:
            Job definition ARN
        """
        # Create a stable job definition name based on job requirements
        job_def_key = self._generate_job_def_key(job_spec)
        
        if job_def_key in self._job_definitions:
            return self._job_definitions[job_def_key]
        
        # Create new job definition
        job_def_name = f"{self.job_definition_name}-{job_def_key}"
        job_def_request = self._build_job_definition(job_spec, job_def_name)
        
        def _register():
            response = self._batch_client.register_job_definition(**job_def_request)
            return response['jobDefinitionArn']
        
        loop = asyncio.get_event_loop()
        job_def_arn = await loop.run_in_executor(None, _register)
        
        self._job_definitions[job_def_key] = job_def_arn
        logger.debug(f"Created job definition {job_def_name}: {job_def_arn}")
        
        return job_def_arn
    
    def _generate_job_def_key(self, job_spec: JobSpec) -> str:
        """Generate a stable key for job definition caching."""
        import hashlib
        
        # Create hash from job requirements
        key_data = {
            'image': job_spec.container.image,
            'cpus': job_spec.resources.cpus,
            'memory': job_spec.resources.memory_mb,
            'gpu': job_spec.resources.gpu,
            'privileged': job_spec.container.privileged,
        }
        
        key_str = json.dumps(key_data, sort_keys=True)
        return hashlib.md5(key_str.encode()).hexdigest()[:8]
    
    def _build_job_definition(self, job_spec: JobSpec, job_def_name: str) -> Dict[str, Any]:
        """
        Build AWS Batch job definition from job spec.
        
        Args:
            job_spec: Job specification
            job_def_name: Job definition name
            
        Returns:
            Job definition request
        """
        container_props = {
            'image': job_spec.container.image,
            'vcpus': job_spec.resources.cpus,
            'memory': job_spec.resources.memory_mb,
        }
        
        # Environment variables
        if job_spec.container.env:
            container_props['environment'] = [
                {'name': k, 'value': v} for k, v in job_spec.container.env.items()
            ]
        
        # Job role for AWS permissions
        job_role = self.config.get('job_role_arn')
        if job_role:
            container_props['jobRoleArn'] = job_role
        
        # Execution role for Fargate
        execution_role = self.config.get('execution_role_arn')
        if execution_role:
            container_props['executionRoleArn'] = execution_role
        
        # GPU resources
        if job_spec.resources.gpu and job_spec.resources.gpu > 0:
            container_props['resourceRequirements'] = [
                {
                    'type': 'GPU',
                    'value': str(job_spec.resources.gpu)
                }
            ]
        
        # Privileged mode
        if job_spec.container.privileged:
            container_props['privileged'] = True
        
        # Note: AWS Batch doesn't support workingDirectory parameter
        # The working directory must be set in the Docker image or via command
        # If needed, prepend 'cd <dir> &&' to the command
        
        # Mount points for EFS or other storage
        mount_points = self._build_mount_points(job_spec)
        if mount_points:
            container_props['mountPoints'] = mount_points
            container_props['volumes'] = self._build_volumes(job_spec)
        
        job_definition = {
            'jobDefinitionName': job_def_name,
            'type': 'container',
            'containerProperties': container_props,
        }
        
        # Spot retry strategy
        if self.max_spot_attempts > 0:
            job_definition['retryStrategy'] = {
                'attempts': self.max_spot_attempts
            }
        
        # Timeout
        if job_spec.timeout_seconds:
            job_definition['timeout'] = {
                'attemptDurationSeconds': job_spec.timeout_seconds
            }
        
        return job_definition
    
    def _build_mount_points(self, job_spec: JobSpec) -> List[Dict[str, Any]]:
        """Build mount points for the job."""
        mount_points = []

        # Add Docker socket mount for Docker-in-Docker (fetch-and-run mode)
        # Check if this is a fetch-and-run job by examining the image
        if 'fetch-and-run' in job_spec.container.image:
            mount_points.append({
                'sourceVolume': 'docker_socket',
                'containerPath': '/var/run/docker.sock',
                'readOnly': False
            })
            logger.info(f"Added Docker socket mount for fetch-and-run container")

            # Mount host /tmp for Docker-in-Docker file sharing
            # Fetch-and-run creates files at /host-tmp/galaxy_execution_{job_id}/
            # Tool containers then mount the same files from host /tmp/ via docker -v
            mount_points.append({
                'sourceVolume': 'host_tmp',
                'containerPath': '/host-tmp',
                'readOnly': False
            })
            logger.info(f"Added host /tmp mount at /host-tmp for Docker-in-Docker file sharing")

        # Add EFS mounts if configured
        efs_mounts = self.config.get('efs_mounts', [])
        for mount in efs_mounts:
            mount_points.append({
                'sourceVolume': mount['name'],
                'containerPath': mount['container_path'],
                'readOnly': mount.get('read_only', False)
            })

        return mount_points
    
    def _build_volumes(self, job_spec: JobSpec) -> List[Dict[str, Any]]:
        """Build volumes for the job."""
        volumes = []

        # Add Docker socket volume for Docker-in-Docker (fetch-and-run mode)
        # Use 'host' volume type to mount the host's Docker socket
        if 'fetch-and-run' in job_spec.container.image:
            volumes.append({
                'name': 'docker_socket',
                'host': {
                    'sourcePath': '/var/run/docker.sock'
                }
            })
            logger.info(f"Added Docker socket volume (host path: /var/run/docker.sock)")

            # Add host /tmp volume for Docker-in-Docker file sharing
            # Fetch-and-run writes to /host-tmp/galaxy_execution_{job_id}/
            # Tool containers mount /tmp/galaxy_execution_{job_id}/ directly from host
            volumes.append({
                'name': 'host_tmp',
                'host': {
                    'sourcePath': '/tmp'
                }
            })
            logger.info(f"Added host /tmp volume for Docker-in-Docker file sharing")

        # Add EFS volumes if configured
        efs_mounts = self.config.get('efs_mounts', [])
        for mount in efs_mounts:
            volumes.append({
                'name': mount['name'],
                'efsVolumeConfiguration': {
                    'fileSystemId': mount['file_system_id'],
                    'rootDirectory': mount.get('root_directory', '/'),
                    'transitEncryption': mount.get('transit_encryption', 'ENABLED'),
                    'authorizationConfig': mount.get('authorization_config', {})
                }
            })

        return volumes
    
    async def _build_submit_request(self, job_spec: JobSpec, job_def_arn: str) -> Dict[str, Any]:
        """
        Build job submission request.
        
        Args:
            job_spec: Job specification
            job_def_arn: Job definition ARN
            
        Returns:
            Job submission request
        """
        # Sanitize job name for AWS Batch (only alphanumeric, hyphens, underscores)
        import re
        job_name = job_spec.name or job_spec.job_id
        job_name = re.sub(r'[^a-zA-Z0-9_-]', '-', job_name)
        # Ensure it doesn't exceed 128 characters
        job_name = job_name[:128]

        submit_request = {
            'jobName': job_name,
            'jobQueue': self.job_queue,
            'jobDefinition': job_def_arn,
        }
        
        # Job parameters
        # CRITICAL FIX 15: Always use containerOverrides for environment variables
        # Even if there's no command/args, we need to override env vars per job
        # Otherwise, job definition env vars get cached and reused across different jobs!
        container_overrides = {}

        if job_spec.container.command:
            container_overrides['command'] = job_spec.container.command
        elif job_spec.container.args:
            # If no command specified, use args as command
            container_overrides['command'] = job_spec.container.args

        # ALWAYS set environment variables as override (Fix 15)
        # This ensures each job gets its unique JOB_ID, not cached values
        if job_spec.container.env:
            container_overrides['environment'] = [
                {'name': k, 'value': str(v)} for k, v in job_spec.container.env.items()
            ]
            logger.debug(f"Setting {len(job_spec.container.env)} environment variable(s) for job {job_spec.job_id}")

        # Only add containerOverrides if there's something to override
        if container_overrides:
            submit_request['containerOverrides'] = container_overrides
        
        # Tags
        if job_spec.labels:
            submit_request['tags'] = job_spec.labels
        
        # Job arrays for parallel processing
        array_size = job_spec.cloud_options.get('array_size')
        if array_size and array_size > 1:
            submit_request['arrayProperties'] = {
                'size': array_size
            }
        
        return submit_request
    
    async def _upload_input_files(self, job_spec: JobSpec) -> None:
        """Upload input files to S3.

        Note: input_files mapping can contain either:
        - local_path -> container_path (needs upload)
        - s3_uri -> container_path (already on S3, skip upload)
        """
        if not self._s3_client or not job_spec.input_files:
            return

        upload_tasks = []
        for source_path, container_path in job_spec.input_files.items():
            # Skip if source is already an S3 URI
            if source_path.startswith('s3://'):
                self.logger.debug(f"Skipping upload for S3 URI: {source_path}")
                continue

            # For local files, upload to S3
            if not container_path.startswith('s3://'):
                s3_uri = f"s3://{self.s3_bucket}/{self.s3_prefix}/{job_spec.job_id}/{container_path}"
            else:
                s3_uri = container_path

            upload_tasks.append(self._upload_file_to_s3(source_path, s3_uri))

        if upload_tasks:
            await asyncio.gather(*upload_tasks)
    
    async def _upload_file_to_s3(self, local_path: str, s3_uri: str) -> None:
        """Upload a single file to S3."""
        from urllib.parse import urlparse
        
        parsed = urlparse(s3_uri)
        bucket = parsed.netloc
        key = parsed.path.lstrip('/')
        
        def _upload():
            self._s3_client.upload_file(local_path, bucket, key)
        
        loop = asyncio.get_event_loop()
        await loop.run_in_executor(None, _upload)
    
    async def get_job_status(self, cloud_job_id: str) -> JobStatus:
        """
        Get the current status of an AWS Batch job.
        
        Args:
            cloud_job_id: AWS Batch job ID
            
        Returns:
            Current job status
        """
        self._ensure_initialized()
        
        def _describe():
            response = self._batch_client.describe_jobs(jobs=[cloud_job_id])
            jobs = response.get('jobs', [])

            if not jobs:
                self.logger.warning(f"No job found for ID {cloud_job_id}")
                return JobStatus.UNKNOWN

            job = jobs[0]
            aws_status = job.get('status')  # AWS Batch uses 'status', not 'jobStatus'

            if not aws_status:
                self.logger.error(f"Job object missing status field: {job.keys()}")
                return JobStatus.UNKNOWN
            
            # Map AWS Batch status to our status
            status_mapping = {
                'SUBMITTED': JobStatus.QUEUED,
                'PENDING': JobStatus.QUEUED,
                'RUNNABLE': JobStatus.QUEUED,
                'STARTING': JobStatus.RUNNING,
                'RUNNING': JobStatus.RUNNING,
                'SUCCEEDED': JobStatus.COMPLETED,
                'FAILED': JobStatus.FAILED,
            }
            
            return status_mapping.get(aws_status, JobStatus.UNKNOWN)
        
        loop = asyncio.get_event_loop()
        return await loop.run_in_executor(None, _describe)
    
    async def get_job_result(self, cloud_job_id: str) -> JobResult:
        """
        Get detailed job result.
        
        Args:
            cloud_job_id: AWS Batch job ID
            
        Returns:
            Complete job result
        """
        self._ensure_initialized()
        
        def _describe():
            response = self._batch_client.describe_jobs(jobs=[cloud_job_id])
            jobs = response.get('jobs', [])
            
            if not jobs:
                raise ValueError(f"Job {cloud_job_id} not found")
            
            return jobs[0]
        
        loop = asyncio.get_event_loop()
        job_data = await loop.run_in_executor(None, _describe)
        
        # Parse job data into result
        result = JobResult(
            job_id=cloud_job_id,
            cloud_job_id=cloud_job_id,
            status=await self.get_job_status(cloud_job_id)
        )
        
        # Timing information
        if 'createdAt' in job_data:
            result.submitted_at = datetime.fromtimestamp(job_data['createdAt'] / 1000)
        
        if 'startedAt' in job_data:
            result.started_at = datetime.fromtimestamp(job_data['startedAt'] / 1000)
        
        if 'stoppedAt' in job_data:
            result.finished_at = datetime.fromtimestamp(job_data['stoppedAt'] / 1000)
        
        # Exit code and reason
        if 'attempts' in job_data and job_data['attempts']:
            attempt = job_data['attempts'][-1]  # Latest attempt

            # Get container info from attempt
            container = attempt.get('container', {})
            if 'exitCode' in container:
                result.exit_code = container['exitCode']

            if 'reason' in container:
                result.error_message = container['reason']

        # Also check top-level statusReason
        if not result.error_message and 'statusReason' in job_data:
            result.error_message = job_data['statusReason']

        # Check container-level reason
        if not result.error_message and 'container' in job_data:
            container = job_data['container']
            if 'reason' in container:
                result.error_message = container['reason']
            if 'exitCode' in container and not result.exit_code:
                result.exit_code = container['exitCode']
        
        # Get logs
        logs = await self._get_job_logs(cloud_job_id, job_data)
        if logs:
            result.stdout = logs.get('stdout', '')
            result.stderr = logs.get('stderr', '')
        
        # Cloud metadata
        result.cloud_metadata = {
            'job_queue': job_data.get('jobQueue'),
            'job_definition': job_data.get('jobDefinition'),
            'status_reason': job_data.get('statusReason'),
        }
        
        return result
    
    async def _get_job_logs(self, job_id: str, job_data: Dict[str, Any]) -> Optional[Dict[str, str]]:
        """Get CloudWatch logs for a job."""
        try:
            # Get log stream name from job attempts
            if 'attempts' not in job_data or not job_data['attempts']:
                return None
            
            attempt = job_data['attempts'][-1]
            log_stream = attempt.get('logStreamName')
            
            if not log_stream:
                return None
            
            # Get logs from CloudWatch
            def _get_logs():
                response = self._logs_client.get_log_events(
                    logGroupName='/aws/batch/job',
                    logStreamName=log_stream,
                    startFromHead=True
                )
                
                events = response.get('events', [])
                log_content = '\n'.join([event['message'] for event in events])
                
                return {
                    'stdout': log_content,
                    'stderr': ''  # AWS Batch combines stdout/stderr
                }
            
            loop = asyncio.get_event_loop()
            return await loop.run_in_executor(None, _get_logs)
            
        except Exception as e:
            logger.warning(f"Failed to get logs for job {job_id}: {e}")
            return None
    
    async def cancel_job(self, cloud_job_id: str) -> bool:
        """
        Cancel an AWS Batch job.
        
        Args:
            cloud_job_id: AWS Batch job ID
            
        Returns:
            True if cancellation was successful
        """
        self._ensure_initialized()
        
        try:
            def _cancel():
                self._batch_client.cancel_job(
                    jobId=cloud_job_id,
                    reason='Cancelled by Galaxy Cloud Executor'
                )
            
            loop = asyncio.get_event_loop()
            await loop.run_in_executor(None, _cancel)
            
            logger.info(f"Cancelled AWS Batch job {cloud_job_id}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to cancel job {cloud_job_id}: {e}")
            return False
    
    async def list_jobs(self, status_filter: Optional[JobStatus] = None) -> List[str]:
        """
        List AWS Batch jobs.
        
        Args:
            status_filter: Optional status filter
            
        Returns:
            List of job IDs
        """
        self._ensure_initialized()
        
        # Map our status to AWS Batch status
        aws_status_filter = None
        if status_filter:
            status_mapping = {
                JobStatus.QUEUED: ['SUBMITTED', 'PENDING', 'RUNNABLE'],
                JobStatus.RUNNING: ['STARTING', 'RUNNING'],
                JobStatus.COMPLETED: ['SUCCEEDED'],
                JobStatus.FAILED: ['FAILED'],
            }
            aws_status_filter = status_mapping.get(status_filter, [])
        
        def _list():
            jobs = []
            
            # AWS Batch requires listing by status
            statuses_to_check = aws_status_filter or ['SUBMITTED', 'PENDING', 'RUNNABLE', 'STARTING', 'RUNNING']
            
            for status in statuses_to_check:
                response = self._batch_client.list_jobs(
                    jobQueue=self.job_queue,
                    jobStatus=status
                )
                jobs.extend([job['jobId'] for job in response.get('jobSummary', [])])
            
            return jobs
        
        loop = asyncio.get_event_loop()
        return await loop.run_in_executor(None, _list)
    
    def get_default_resource_spec(self) -> Dict[str, Any]:
        """Get default resource specifications for AWS Batch."""
        return {
            "cpus": 1,
            "memory_mb": 2048,
            "disk_gb": 10,
        }
    
    def validate_job_spec(self, job_spec: JobSpec) -> None:
        """
        Validate job specification for AWS Batch.
        
        Args:
            job_spec: Job specification to validate
            
        Raises:
            ValueError: If job specification is invalid
        """
        super().validate_job_spec(job_spec)

        # AWS Batch specific validation
        max_cpus = self.resource_limits.get('max_cpus') or 256
        max_memory_mb = self.resource_limits.get('max_memory_mb') or (512 * 1024)

        if job_spec.resources.cpus is not None and job_spec.resources.cpus > max_cpus:
            raise ValueError(f"CPU count exceeds limit: {job_spec.resources.cpus}")

        if job_spec.resources.memory_mb is not None and job_spec.resources.memory_mb > max_memory_mb:
            raise ValueError(f"Memory exceeds limit: {job_spec.resources.memory_mb} MB")
        
        # Validate container image
        if not job_spec.container.image:
            raise ValueError("Container image is required for AWS Batch")
        
        # Validate job queue is configured
        if not self.job_queue:
            raise ValueError("AWS Batch job queue must be configured")