"""
Kubernetes executor implementation.
"""

import asyncio
import yaml
import json
from typing import Dict, Any, Optional, List, Set
from datetime import datetime

from kubernetes_asyncio import client, config
from kubernetes_asyncio.client import ApiClient, V1Job, V1Pod, V1JobStatus, V1PodStatus
from kubernetes_asyncio.client.rest import ApiException

from galaxy_cloud.core.executor import CloudExecutor
from galaxy_cloud.core.job import JobSpec, JobStatus, JobResult, JobEvent
from galaxy_cloud.registry import cloud_executor
from galaxy_cloud.providers.k8s.auth import K8sAuth


@cloud_executor("kubernetes", {
    "description": "Kubernetes executor for container workloads",
    "supported_features": [
        "container_jobs", "job_arrays", "resource_limits", 
        "node_selection", "tolerations", "affinity",
        "persistent_volumes", "config_maps", "secrets"
    ],
    "version": "1.0.0"
})
class KubernetesExecutor(CloudExecutor):
    """Kubernetes executor implementation."""
    
    def __init__(self, config: Dict[str, Any], **kwargs):
        super().__init__(config, **kwargs)
        
        # Kubernetes configuration
        self.namespace = config.get('namespace', 'default')
        self.kubeconfig_path = config.get('kubeconfig_path')
        self.context = config.get('context')
        self.cluster_endpoint = config.get('cluster_endpoint')
        
        # Job configuration
        self.job_name_prefix = config.get('job_name_prefix', 'galaxy-job')
        self.pod_name_prefix = config.get('pod_name_prefix', 'galaxy-pod')
        self.backoff_limit = config.get('backoff_limit', 3)
        self.ttl_seconds_after_finished = config.get('ttl_seconds_after_finished', 3600)
        
        # Resource configuration
        self.default_service_account = config.get('service_account', 'default')
        self.image_pull_policy = config.get('image_pull_policy', 'Always')
        self.image_pull_secrets = config.get('image_pull_secrets', [])
        
        # Node selection
        self.node_selector = config.get('node_selector', {})
        self.tolerations = config.get('tolerations', [])
        self.affinity = config.get('affinity', {})
        
        # Storage configuration
        self.default_storage_class = config.get('storage_class', 'standard')
        self.workspace_volume_size = config.get('workspace_volume_size', '10Gi')
        
        # Security context
        self.security_context = config.get('security_context', {})
        self.pod_security_context = config.get('pod_security_context', {})
        
        # Labels and annotations
        self.default_labels = config.get('labels', {})
        self.default_annotations = config.get('annotations', {})
        
        # Internal state
        self.api_client: Optional[ApiClient] = None
        self.batch_v1: Optional[client.BatchV1Api] = None
        self.core_v1: Optional[client.CoreV1Api] = None
        self.auth_provider: Optional[K8sAuth] = None
        self._active_jobs: Set[str] = set()
        
    async def initialize(self) -> None:
        """Initialize Kubernetes client and authentication."""
        self.auth_provider = K8sAuth(self.config)
        await self.auth_provider.initialize()
        
        # Load Kubernetes configuration
        if self.kubeconfig_path:
            await config.load_kube_config(config_file=self.kubeconfig_path, context=self.context)
        else:
            try:
                # Try in-cluster config first
                config.load_incluster_config()
                self.logger.info("Using in-cluster Kubernetes configuration")
            except config.ConfigException:
                # Fall back to default kubeconfig
                await config.load_kube_config(context=self.context)
                self.logger.info("Using default kubeconfig")
        
        # Initialize API clients
        self.api_client = ApiClient()
        self.batch_v1 = client.BatchV1Api(self.api_client)
        self.core_v1 = client.CoreV1Api(self.api_client)
        
        self._initialized = True
        self.logger.info(f"Kubernetes executor initialized for namespace: {self.namespace}")
    
    async def cleanup(self) -> None:
        """Clean up Kubernetes resources."""
        if self.api_client:
            await self.api_client.close()
            
        if self.auth_provider:
            await self.auth_provider.cleanup()
        
        self._initialized = False
        self.logger.info("Kubernetes executor cleaned up")
    
    @property
    def provider_name(self) -> str:
        return "kubernetes"
    
    @property
    def executor_type(self) -> str:
        return "job"
    
    async def submit_job(self, job_spec: JobSpec) -> str:
        """Submit job to Kubernetes."""
        if not self._initialized:
            raise RuntimeError("Executor not initialized")
        
        try:
            # Handle job arrays
            if job_spec.cloud_options.get('array_size'):
                return await self._submit_job_array(job_spec)
            else:
                return await self._submit_single_job(job_spec)
                
        except Exception as e:
            self.logger.error(f"Failed to submit job {job_spec.job_id}: {e}")
            raise
    
    async def _submit_single_job(self, job_spec: JobSpec) -> str:
        """Submit a single job to Kubernetes."""
        
        # Create job manifest
        k8s_job = await self._create_job_manifest(job_spec)
        
        # Submit job
        try:
            response = await self.batch_v1.create_namespaced_job(
                namespace=self.namespace,
                body=k8s_job
            )
            
            job_name = response.metadata.name
            self._active_jobs.add(job_name)
            
            self.logger.info(f"Submitted Kubernetes job: {job_name}")
            return job_name
            
        except ApiException as e:
            self.logger.error(f"Failed to create Kubernetes job: {e}")
            raise
    
    async def _submit_job_array(self, job_spec: JobSpec) -> str:
        """Submit a job array to Kubernetes."""
        array_size = job_spec.cloud_options['array_size']
        
        # Create job with parallelism and completions
        k8s_job = await self._create_job_manifest(job_spec, array_size=array_size)
        
        # Submit job
        try:
            response = await self.batch_v1.create_namespaced_job(
                namespace=self.namespace,
                body=k8s_job
            )
            
            job_name = response.metadata.name
            self._active_jobs.add(job_name)
            
            self.logger.info(f"Submitted Kubernetes job array: {job_name} with {array_size} parallel tasks")
            return job_name
            
        except ApiException as e:
            self.logger.error(f"Failed to create Kubernetes job array: {e}")
            raise
    
    async def get_job_status(self, cloud_job_id: str) -> JobStatus:
        """Get job status from Kubernetes."""
        try:
            response = await self.batch_v1.read_namespaced_job_status(
                name=cloud_job_id,
                namespace=self.namespace
            )
            
            return self._map_k8s_job_status_to_job_status(response.status)
            
        except ApiException as e:
            if e.status == 404:
                return JobStatus.UNKNOWN
            self.logger.error(f"Failed to get status for job {cloud_job_id}: {e}")
            return JobStatus.UNKNOWN
    
    async def get_job_result(self, cloud_job_id: str) -> JobResult:
        """Get detailed job result from Kubernetes."""
        try:
            # Get job details
            job_response = await self.batch_v1.read_namespaced_job_status(
                name=cloud_job_id,
                namespace=self.namespace
            )
            
            job = job_response
            status = job.status
            
            # Get pods for this job
            pods = await self._get_job_pods(cloud_job_id)
            
            # Calculate timing information
            start_time = status.start_time
            completion_time = status.completion_time
            
            # Get exit codes and logs from pods
            exit_codes = []
            stdout_logs = []
            stderr_logs = []
            
            for pod in pods:
                if pod.status.container_statuses:
                    for container_status in pod.status.container_statuses:
                        if container_status.state.terminated:
                            exit_codes.append(container_status.state.terminated.exit_code)
                
                # Get pod logs
                try:
                    pod_logs = await self._get_pod_logs(pod.metadata.name)
                    stdout_logs.append(pod_logs)
                except:
                    pass
            
            # Determine overall exit code
            overall_exit_code = None
            if exit_codes:
                # Use first non-zero exit code, or 0 if all succeeded
                overall_exit_code = next((code for code in exit_codes if code != 0), 0)
            
            # Build result
            result = JobResult(
                job_id=cloud_job_id,
                cloud_job_id=cloud_job_id,
                status=self._map_k8s_job_status_to_job_status(status),
                submitted_at=job.metadata.creation_timestamp,
                started_at=start_time,
                finished_at=completion_time,
                exit_code=overall_exit_code,
                stdout='\n'.join(stdout_logs) if stdout_logs else None,
                cloud_metadata={
                    'namespace': self.namespace,
                    'job_uid': job.metadata.uid,
                    'succeeded': status.succeeded or 0,
                    'failed': status.failed or 0,
                    'active': status.active or 0,
                    'completions': status.completions,
                    'parallelism': job.spec.parallelism,
                    'pod_count': len(pods),
                    'node_names': list(set(pod.spec.node_name for pod in pods if pod.spec.node_name))
                }
            )
            
            # Get error information if failed
            if status.failed and status.failed > 0:
                failed_pods = [pod for pod in pods if pod.status.phase == 'Failed']
                error_messages = []
                
                for pod in failed_pods:
                    if pod.status.container_statuses:
                        for container_status in pod.status.container_statuses:
                            if container_status.state.terminated and container_status.state.terminated.reason:
                                error_messages.append(
                                    f"Pod {pod.metadata.name}: {container_status.state.terminated.reason}"
                                )
                
                if error_messages:
                    result.error_message = "; ".join(error_messages[:3])  # First 3 errors
                    result.error_details = {
                        'failed_pod_count': len(failed_pods),
                        'error_messages': error_messages
                    }
            
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
        """Cancel job in Kubernetes."""
        try:
            # Delete the job
            await self.batch_v1.delete_namespaced_job(
                name=cloud_job_id,
                namespace=self.namespace,
                propagation_policy='Background'  # Delete dependent pods
            )
            
            self._active_jobs.discard(cloud_job_id)
            self.logger.info(f"Cancelled Kubernetes job: {cloud_job_id}")
            return True
            
        except ApiException as e:
            if e.status == 404:
                # Job already doesn't exist
                return True
            self.logger.error(f"Failed to cancel job {cloud_job_id}: {e}")
            return False
    
    async def list_jobs(self, status_filter: Optional[JobStatus] = None) -> List[str]:
        """List jobs in Kubernetes."""
        try:
            response = await self.batch_v1.list_namespaced_job(namespace=self.namespace)
            job_names = []
            
            for job in response.items:
                if status_filter:
                    job_status = self._map_k8s_job_status_to_job_status(job.status)
                    if job_status == status_filter:
                        job_names.append(job.metadata.name)
                else:
                    job_names.append(job.metadata.name)
            
            return job_names
            
        except Exception as e:
            self.logger.error(f"Failed to list jobs: {e}")
            return []
    
    # Helper methods
    
    def _map_k8s_job_status_to_job_status(self, status: V1JobStatus) -> JobStatus:
        """Map Kubernetes job status to JobStatus."""
        if status.active and status.active > 0:
            return JobStatus.RUNNING
        elif status.succeeded and status.succeeded > 0:
            return JobStatus.COMPLETED
        elif status.failed and status.failed > 0:
            return JobStatus.FAILED
        else:
            return JobStatus.QUEUED
    
    async def _create_job_manifest(self, job_spec: JobSpec, array_size: int = None) -> V1Job:
        """Create Kubernetes Job manifest."""
        
        # Generate unique job name
        job_name = f"{self.job_name_prefix}-{job_spec.job_id}-{int(datetime.utcnow().timestamp())}"
        
        # Create container spec
        container = client.V1Container(
            name=job_spec.job_id,
            image=job_spec.container.image,
            command=job_spec.container.command,
            args=job_spec.container.args,
            env=self._create_env_vars(job_spec),
            resources=self._create_resource_requirements(job_spec),
            volume_mounts=await self._create_volume_mounts(job_spec),
            working_dir=job_spec.container.working_dir,
            image_pull_policy=self.image_pull_policy,
            security_context=self._create_security_context(job_spec)
        )
        
        # Create pod template
        pod_template = client.V1PodTemplateSpec(
            metadata=client.V1ObjectMeta(
                labels=self._merge_labels(job_spec.labels, {'job': job_name}),
                annotations=self._merge_annotations(job_spec.annotations)
            ),
            spec=client.V1PodSpec(
                containers=[container],
                restart_policy='Never',
                service_account_name=self.default_service_account,
                node_selector=self._merge_node_selector(job_spec.cloud_options.get('node_selector', {})),
                tolerations=self._create_tolerations(job_spec.cloud_options.get('tolerations', [])),
                affinity=self._create_affinity(job_spec.cloud_options.get('affinity', {})),
                volumes=await self._create_volumes(job_spec),
                image_pull_secrets=self._create_image_pull_secrets(),
                security_context=self._create_pod_security_context(job_spec),
                hostname=job_spec.cloud_options.get('hostname'),
                subdomain=job_spec.cloud_options.get('subdomain')
            )
        )
        
        # Configure job parallelism
        parallelism = 1
        completions = 1
        
        if array_size:
            parallelism = min(array_size, job_spec.cloud_options.get('max_parallel_tasks', array_size))
            completions = array_size
            
            # Add array index environment variable
            container.env.append(client.V1EnvVar(
                name='JOB_COMPLETION_INDEX',
                value_from=client.V1EnvVarSource(
                    field_ref=client.V1ObjectFieldSelector(
                        field_path='metadata.annotations[\'batch.kubernetes.io/job-completion-index\']'
                    )
                )
            ))
        
        # Create job spec
        job_spec_k8s = client.V1JobSpec(
            template=pod_template,
            parallelism=parallelism,
            completions=completions,
            backoff_limit=max(job_spec.retry_attempts, self.backoff_limit),
            ttl_seconds_after_finished=self.ttl_seconds_after_finished,
            active_deadline_seconds=job_spec.timeout_seconds
        )
        
        # Create job
        job = client.V1Job(
            api_version='batch/v1',
            kind='Job',
            metadata=client.V1ObjectMeta(
                name=job_name,
                namespace=self.namespace,
                labels=self._merge_labels(job_spec.labels, {'component': 'job'}),
                annotations=self._merge_annotations(job_spec.annotations)
            ),
            spec=job_spec_k8s
        )
        
        return job
    
    def _create_env_vars(self, job_spec: JobSpec) -> List[client.V1EnvVar]:
        """Create environment variables for the container."""
        env_vars = []
        
        for name, value in job_spec.container.env.items():
            env_vars.append(client.V1EnvVar(name=name, value=str(value)))
        
        # Add system environment variables
        env_vars.extend([
            client.V1EnvVar(
                name='KUBERNETES_NODE_NAME',
                value_from=client.V1EnvVarSource(
                    field_ref=client.V1ObjectFieldSelector(field_path='spec.nodeName')
                )
            ),
            client.V1EnvVar(
                name='KUBERNETES_POD_NAME',
                value_from=client.V1EnvVarSource(
                    field_ref=client.V1ObjectFieldSelector(field_path='metadata.name')
                )
            ),
            client.V1EnvVar(
                name='KUBERNETES_NAMESPACE',
                value_from=client.V1EnvVarSource(
                    field_ref=client.V1ObjectFieldSelector(field_path='metadata.namespace')
                )
            )
        ])
        
        return env_vars
    
    def _create_resource_requirements(self, job_spec: JobSpec) -> client.V1ResourceRequirements:
        """Create resource requirements for the container."""
        requests = {}
        limits = {}
        
        # CPU
        if job_spec.resources.cpus:
            cpu_value = f"{job_spec.resources.cpus}"
            requests['cpu'] = cpu_value
            limits['cpu'] = cpu_value
        
        # Memory
        if job_spec.resources.memory_mb:
            memory_value = f"{job_spec.resources.memory_mb}Mi"
            requests['memory'] = memory_value
            limits['memory'] = memory_value
        
        # GPU
        if job_spec.resources.gpu and job_spec.resources.gpu > 0:
            gpu_resource = job_spec.resources.gpu_type or 'nvidia.com/gpu'
            gpu_value = str(job_spec.resources.gpu)
            requests[gpu_resource] = gpu_value
            limits[gpu_resource] = gpu_value
        
        return client.V1ResourceRequirements(
            requests=requests if requests else None,
            limits=limits if limits else None
        )
    
    async def _create_volumes(self, job_spec: JobSpec) -> List[client.V1Volume]:
        """Create volumes for the pod."""
        volumes = []
        
        # Create workspace volume if needed
        if job_spec.input_files or job_spec.output_files:
            volumes.append(client.V1Volume(
                name='workspace',
                empty_dir=client.V1EmptyDirVolumeSource()
            ))
        
        # Add custom volumes from cloud options
        custom_volumes = job_spec.cloud_options.get('volumes', [])
        for volume_config in custom_volumes:
            volume = await self._create_volume_from_config(volume_config)
            if volume:
                volumes.append(volume)
        
        return volumes
    
    async def _create_volume_mounts(self, job_spec: JobSpec) -> List[client.V1VolumeMount]:
        """Create volume mounts for the container."""
        mounts = []
        
        # Mount workspace volume
        if job_spec.input_files or job_spec.output_files:
            mounts.append(client.V1VolumeMount(
                name='workspace',
                mount_path='/workspace'
            ))
        
        # Add custom volume mounts
        custom_mounts = job_spec.cloud_options.get('volume_mounts', [])
        for mount_config in custom_mounts:
            mount = client.V1VolumeMount(
                name=mount_config['name'],
                mount_path=mount_config['mount_path'],
                read_only=mount_config.get('read_only', False),
                sub_path=mount_config.get('sub_path')
            )
            mounts.append(mount)
        
        return mounts
    
    async def _create_volume_from_config(self, volume_config: Dict[str, Any]) -> Optional[client.V1Volume]:
        """Create a volume from configuration."""
        volume_type = volume_config.get('type')
        name = volume_config.get('name')
        
        if not name or not volume_type:
            return None
        
        if volume_type == 'emptyDir':
            return client.V1Volume(
                name=name,
                empty_dir=client.V1EmptyDirVolumeSource(
                    size_limit=volume_config.get('size_limit')
                )
            )
        
        elif volume_type == 'configMap':
            return client.V1Volume(
                name=name,
                config_map=client.V1ConfigMapVolumeSource(
                    name=volume_config.get('config_map_name'),
                    default_mode=volume_config.get('default_mode')
                )
            )
        
        elif volume_type == 'secret':
            return client.V1Volume(
                name=name,
                secret=client.V1SecretVolumeSource(
                    secret_name=volume_config.get('secret_name'),
                    default_mode=volume_config.get('default_mode')
                )
            )
        
        elif volume_type == 'persistentVolumeClaim':
            return client.V1Volume(
                name=name,
                persistent_volume_claim=client.V1PersistentVolumeClaimVolumeSource(
                    claim_name=volume_config.get('claim_name'),
                    read_only=volume_config.get('read_only', False)
                )
            )
        
        return None
    
    def _create_security_context(self, job_spec: JobSpec) -> Optional[client.V1SecurityContext]:
        """Create security context for the container."""
        if not self.security_context and not job_spec.container.privileged:
            return None
        
        security_context = client.V1SecurityContext()
        
        if job_spec.container.privileged:
            security_context.privileged = True
        
        # Apply configured security context
        for key, value in self.security_context.items():
            setattr(security_context, key, value)
        
        return security_context
    
    def _create_pod_security_context(self, job_spec: JobSpec) -> Optional[client.V1PodSecurityContext]:
        """Create pod security context."""
        if not self.pod_security_context:
            return None
        
        pod_security_context = client.V1PodSecurityContext()
        
        for key, value in self.pod_security_context.items():
            setattr(pod_security_context, key, value)
        
        return pod_security_context
    
    def _create_tolerations(self, tolerations_config: List[Dict[str, Any]]) -> List[client.V1Toleration]:
        """Create tolerations from configuration."""
        tolerations = []
        
        # Add default tolerations
        for toleration_config in self.tolerations:
            tolerations.append(client.V1Toleration(**toleration_config))
        
        # Add job-specific tolerations
        for toleration_config in tolerations_config:
            tolerations.append(client.V1Toleration(**toleration_config))
        
        return tolerations
    
    def _create_affinity(self, affinity_config: Dict[str, Any]) -> Optional[client.V1Affinity]:
        """Create affinity from configuration."""
        if not affinity_config and not self.affinity:
            return None
        
        # Merge default and job-specific affinity
        merged_affinity = self.affinity.copy()
        merged_affinity.update(affinity_config)
        
        # This is simplified - in practice you'd need to properly construct
        # V1NodeAffinity, V1PodAffinity, etc. from the configuration
        return None  # Placeholder
    
    def _create_image_pull_secrets(self) -> List[client.V1LocalObjectReference]:
        """Create image pull secrets."""
        return [
            client.V1LocalObjectReference(name=secret_name)
            for secret_name in self.image_pull_secrets
        ]
    
    def _merge_labels(self, job_labels: Dict[str, str], system_labels: Dict[str, str] = None) -> Dict[str, str]:
        """Merge job labels with default and system labels."""
        labels = self.default_labels.copy()
        labels.update(job_labels)
        
        if system_labels:
            labels.update(system_labels)
        
        # Add system labels
        labels.update({
            'created-by': 'galaxy-cloud-executor',
            'provider': 'kubernetes'
        })
        
        return labels
    
    def _merge_annotations(self, job_annotations: Dict[str, str]) -> Dict[str, str]:
        """Merge job annotations with default annotations."""
        annotations = self.default_annotations.copy()
        annotations.update(job_annotations)
        return annotations
    
    def _merge_node_selector(self, job_node_selector: Dict[str, str]) -> Dict[str, str]:
        """Merge job node selector with default node selector."""
        node_selector = self.node_selector.copy()
        node_selector.update(job_node_selector)
        return node_selector
    
    async def _get_job_pods(self, job_name: str) -> List[V1Pod]:
        """Get pods for a specific job."""
        try:
            response = await self.core_v1.list_namespaced_pod(
                namespace=self.namespace,
                label_selector=f'job-name={job_name}'
            )
            
            return response.items
            
        except ApiException as e:
            self.logger.error(f"Failed to get pods for job {job_name}: {e}")
            return []
    
    async def _get_pod_logs(self, pod_name: str) -> str:
        """Get logs from a pod."""
        try:
            response = await self.core_v1.read_namespaced_pod_log(
                name=pod_name,
                namespace=self.namespace,
                tail_lines=1000  # Limit log size
            )
            
            return response
            
        except ApiException as e:
            self.logger.warning(f"Failed to get logs for pod {pod_name}: {e}")
            return ""
    
    async def get_job_logs(self, cloud_job_id: str) -> Dict[str, str]:
        """Get logs for all pods in a job."""
        try:
            pods = await self._get_job_pods(cloud_job_id)
            logs = {}
            
            for pod in pods:
                pod_name = pod.metadata.name
                pod_logs = await self._get_pod_logs(pod_name)
                logs[pod_name] = pod_logs
            
            return logs
            
        except Exception as e:
            self.logger.error(f"Failed to get job logs for {cloud_job_id}: {e}")
            return {}
    
    async def get_job_events(self, cloud_job_id: str) -> List[JobEvent]:
        """Get events for a job."""
        try:
            # Get job events
            job_events = await self.core_v1.list_namespaced_event(
                namespace=self.namespace,
                field_selector=f'involvedObject.name={cloud_job_id}'
            )
            
            # Get pod events
            pods = await self._get_job_pods(cloud_job_id)
            pod_events = []
            
            for pod in pods:
                pod_name = pod.metadata.name
                events = await self.core_v1.list_namespaced_event(
                    namespace=self.namespace,
                    field_selector=f'involvedObject.name={pod_name}'
                )
                pod_events.extend(events.items)
            
            # Convert to JobEvent objects
            events = []
            
            for event in job_events.items + pod_events:
                job_event = JobEvent(
                    job_id=cloud_job_id,
                    event_type=event.reason.lower() if event.reason else 'unknown',
                    message=event.message or '',
                    timestamp=event.event_time or event.first_timestamp,
                    details={
                        'object_kind': event.involved_object.kind,
                        'object_name': event.involved_object.name,
                        'reason': event.reason,
                        'type': event.type,
                        'count': event.count
                    }
                )
                events.append(job_event)
            
            # Sort events by timestamp
            events.sort(key=lambda e: e.timestamp or datetime.min)
            
            return events
            
        except Exception as e:
            self.logger.error(f"Failed to get job events for {cloud_job_id}: {e}")
            return []