"""
Base cloud executor interface and implementation.
Inspired by Nextflow's Executor design pattern.
"""

import asyncio
import logging
from abc import ABC, abstractmethod
from typing import Dict, Any, Optional, List, AsyncIterator
from contextlib import asynccontextmanager

from .job import JobSpec, JobStatus, JobResult, JobEvent

logger = logging.getLogger(__name__)


class CloudExecutor(ABC):
    """
    Abstract base class for cloud executors.
    
    Inspired by Nextflow's Executor interface, this class defines the contract
    for executing jobs on various cloud platforms.
    """
    
    def __init__(self, config: Dict[str, Any], **kwargs):
        """
        Initialize the cloud executor.
        
        Args:
            config: Cloud provider configuration
            **kwargs: Additional initialization parameters
        """
        self.config = config
        self.logger = logging.getLogger(f"{self.__class__.__module__}.{self.__class__.__name__}")
        self._initialized = False
        self._jobs: Dict[str, JobResult] = {}
    
    async def __aenter__(self):
        """Async context manager entry."""
        await self.initialize()
        return self
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager exit."""
        await self.cleanup()
    
    @abstractmethod
    async def initialize(self) -> None:
        """
        Initialize the executor and establish cloud connections.
        Must be called before using the executor.
        """
        pass
    
    @abstractmethod
    async def cleanup(self) -> None:
        """
        Clean up resources and close connections.
        Should be called when done with the executor.
        """
        pass
    
    @property
    @abstractmethod
    def provider_name(self) -> str:
        """Return the cloud provider name (e.g., 'aws', 'azure', 'gcp', 'k8s')."""
        pass
    
    @property
    @abstractmethod
    def executor_type(self) -> str:
        """Return the executor type (e.g., 'batch', 'container-instance')."""
        pass
    
    @property
    def is_initialized(self) -> bool:
        """Check if the executor is initialized."""
        return self._initialized
    
    def _ensure_initialized(self) -> None:
        """Ensure the executor is initialized."""
        if not self._initialized:
            raise RuntimeError(f"{self.__class__.__name__} not initialized. Call initialize() first.")
    
    @abstractmethod
    async def submit_job(self, job_spec: JobSpec) -> str:
        """
        Submit a job for execution.
        
        Args:
            job_spec: Complete job specification
            
        Returns:
            Cloud provider job ID
            
        Raises:
            RuntimeError: If submission fails
        """
        pass
    
    @abstractmethod
    async def get_job_status(self, cloud_job_id: str) -> JobStatus:
        """
        Get the current status of a job.
        
        Args:
            cloud_job_id: Cloud provider job ID
            
        Returns:
            Current job status
        """
        pass
    
    @abstractmethod
    async def get_job_result(self, cloud_job_id: str) -> JobResult:
        """
        Get detailed job result including logs and metadata.
        
        Args:
            cloud_job_id: Cloud provider job ID
            
        Returns:
            Complete job result
        """
        pass
    
    @abstractmethod
    async def cancel_job(self, cloud_job_id: str) -> bool:
        """
        Cancel a running job.
        
        Args:
            cloud_job_id: Cloud provider job ID
            
        Returns:
            True if cancellation was successful, False otherwise
        """
        pass
    
    @abstractmethod
    async def list_jobs(self, status_filter: Optional[JobStatus] = None) -> List[str]:
        """
        List all jobs, optionally filtered by status.
        
        Args:
            status_filter: Optional status filter
            
        Returns:
            List of cloud job IDs
        """
        pass
    
    async def wait_for_completion(
        self, 
        cloud_job_id: str, 
        poll_interval: float = 30.0,
        timeout: Optional[float] = None
    ) -> JobResult:
        """
        Wait for a job to complete.
        
        Args:
            cloud_job_id: Cloud provider job ID
            poll_interval: Polling interval in seconds
            timeout: Optional timeout in seconds
            
        Returns:
            Final job result
            
        Raises:
            asyncio.TimeoutError: If timeout is reached
            RuntimeError: If job fails
        """
        start_time = asyncio.get_event_loop().time()
        
        while True:
            status = await self.get_job_status(cloud_job_id)
            
            if status in (JobStatus.COMPLETED, JobStatus.FAILED, JobStatus.CANCELLED):
                result = await self.get_job_result(cloud_job_id)
                if status == JobStatus.FAILED:
                    raise RuntimeError(f"Job {cloud_job_id} failed: {result.error_message}")
                return result
            
            # Check timeout
            if timeout and (asyncio.get_event_loop().time() - start_time) > timeout:
                raise asyncio.TimeoutError(f"Job {cloud_job_id} did not complete within {timeout} seconds")
            
            await asyncio.sleep(poll_interval)
    
    @asynccontextmanager
    async def job_monitor(
        self, 
        cloud_job_id: str, 
        poll_interval: float = 30.0
    ) -> AsyncIterator[JobEvent]:
        """
        Monitor a job and yield status events.
        
        Args:
            cloud_job_id: Cloud provider job ID
            poll_interval: Polling interval in seconds
            
        Yields:
            Job events as they occur
        """
        last_status = None
        
        try:
            while True:
                current_status = await self.get_job_status(cloud_job_id)
                
                # Emit status change event
                if current_status != last_status:
                    yield JobEvent(
                        job_id=cloud_job_id,
                        event_type="status_change",
                        message=f"Job status changed from {last_status} to {current_status}",
                        details={"old_status": last_status, "new_status": current_status}
                    )
                    last_status = current_status
                
                # Exit if job is complete
                if current_status in (JobStatus.COMPLETED, JobStatus.FAILED, JobStatus.CANCELLED):
                    break
                
                await asyncio.sleep(poll_interval)
                
        except Exception as e:
            yield JobEvent(
                job_id=cloud_job_id,
                event_type="error",
                message=f"Error monitoring job: {str(e)}",
                details={"error": str(e), "error_type": type(e).__name__}
            )
    
    async def bulk_submit(self, job_specs: List[JobSpec]) -> List[str]:
        """
        Submit multiple jobs in bulk.
        
        Args:
            job_specs: List of job specifications
            
        Returns:
            List of cloud job IDs
        """
        tasks = [self.submit_job(spec) for spec in job_specs]
        return await asyncio.gather(*tasks)
    
    async def bulk_status(self, cloud_job_ids: List[str]) -> Dict[str, JobStatus]:
        """
        Get status for multiple jobs in bulk.
        
        Args:
            cloud_job_ids: List of cloud job IDs
            
        Returns:
            Mapping of job IDs to statuses
        """
        tasks = [self.get_job_status(job_id) for job_id in cloud_job_ids]
        statuses = await asyncio.gather(*tasks)
        return dict(zip(cloud_job_ids, statuses))
    
    def validate_job_spec(self, job_spec: JobSpec) -> None:
        """
        Validate a job specification for this executor.
        
        Args:
            job_spec: Job specification to validate
            
        Raises:
            ValueError: If job specification is invalid
        """
        # Basic validation
        if not job_spec.job_id:
            raise ValueError("Job ID is required")
        
        if not job_spec.container.image:
            raise ValueError("Container image is required")
        
        # Resource validation
        if job_spec.resources.cpus < 1:
            raise ValueError("At least 1 CPU core is required")
        
        if job_spec.resources.memory_mb < 1:
            raise ValueError("At least 1 MB of memory is required")
    
    def get_default_resource_spec(self) -> Dict[str, Any]:
        """
        Get default resource specifications for this executor.
        
        Returns:
            Default resource configuration
        """
        return {
            "cpus": 1,
            "memory_mb": 1024,
            "disk_gb": 10,
        }
    
    async def health_check(self) -> Dict[str, Any]:
        """
        Perform a health check on the executor.
        
        Returns:
            Health check results
        """
        try:
            self._ensure_initialized()
            
            # Try to list jobs to verify connectivity
            await self.list_jobs()
            
            return {
                "status": "healthy",
                "provider": self.provider_name,
                "executor_type": self.executor_type,
                "initialized": self._initialized,
            }
        except Exception as e:
            return {
                "status": "unhealthy",
                "provider": self.provider_name,
                "executor_type": self.executor_type,
                "initialized": self._initialized,
                "error": str(e),
            }