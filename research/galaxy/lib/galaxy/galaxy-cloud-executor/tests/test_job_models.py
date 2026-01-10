"""
Tests for job models and status definitions.
"""

import pytest
from datetime import datetime
from pydantic import ValidationError

from galaxy_cloud.core.job import (
    JobStatus,
    ResourceSpec,
    ContainerSpec,
    JobSpec,
    JobResult,
    JobEvent
)


class TestJobStatus:
    """Test JobStatus enumeration."""
    
    def test_job_status_values(self):
        """Test JobStatus enum values."""
        assert JobStatus.PENDING == "pending"
        assert JobStatus.QUEUED == "queued"
        assert JobStatus.RUNNING == "running"
        assert JobStatus.COMPLETED == "completed"
        assert JobStatus.FAILED == "failed"
        assert JobStatus.CANCELLED == "cancelled"
        assert JobStatus.UNKNOWN == "unknown"
    
    def test_job_status_comparison(self):
        """Test JobStatus comparison."""
        assert JobStatus.PENDING != JobStatus.RUNNING
        assert JobStatus.COMPLETED == "completed"
        assert str(JobStatus.FAILED) == "failed"


class TestResourceSpec:
    """Test ResourceSpec model."""
    
    def test_default_resources(self):
        """Test default resource values."""
        spec = ResourceSpec()
        
        assert spec.cpus == 1
        assert spec.memory_mb == 1024
        assert spec.disk_gb is None
        assert spec.gpu is None
        assert spec.gpu_type is None
    
    def test_valid_resources(self):
        """Test valid resource specification."""
        spec = ResourceSpec(
            cpus=4,
            memory_mb=8192,
            disk_gb=100,
            gpu=2,
            gpu_type="nvidia.com/gpu"
        )
        
        assert spec.cpus == 4
        assert spec.memory_mb == 8192
        assert spec.disk_gb == 100
        assert spec.gpu == 2
        assert spec.gpu_type == "nvidia.com/gpu"
    
    def test_invalid_resources(self):
        """Test invalid resource values."""
        # CPU must be >= 1
        with pytest.raises(ValidationError):
            ResourceSpec(cpus=0)
        
        # Memory must be >= 1
        with pytest.raises(ValidationError):
            ResourceSpec(memory_mb=0)
        
        # Disk must be >= 1 if specified
        with pytest.raises(ValidationError):
            ResourceSpec(disk_gb=0)
        
        # GPU must be >= 0 if specified
        with pytest.raises(ValidationError):
            ResourceSpec(gpu=-1)


class TestContainerSpec:
    """Test ContainerSpec model."""
    
    def test_minimal_container(self):
        """Test minimal container specification."""
        spec = ContainerSpec(image="ubuntu:20.04")
        
        assert spec.image == "ubuntu:20.04"
        assert spec.command is None
        assert spec.args is None
        assert spec.env == {}
        assert spec.working_dir is None
        assert not spec.privileged
    
    def test_full_container(self):
        """Test full container specification."""
        spec = ContainerSpec(
            image="python:3.9",
            command=["/bin/bash", "-c"],
            args=["python script.py"],
            env={"PYTHONPATH": "/app", "DEBUG": "1"},
            working_dir="/workspace",
            privileged=True
        )
        
        assert spec.image == "python:3.9"
        assert spec.command == ["/bin/bash", "-c"]
        assert spec.args == ["python script.py"]
        assert spec.env["PYTHONPATH"] == "/app"
        assert spec.env["DEBUG"] == "1"
        assert spec.working_dir == "/workspace"
        assert spec.privileged
    
    def test_container_validation(self):
        """Test container specification validation."""
        # Image is required
        with pytest.raises(ValidationError):
            ContainerSpec()


class TestJobSpec:
    """Test JobSpec model."""
    
    def test_minimal_job_spec(self):
        """Test minimal job specification."""
        spec = JobSpec(
            job_id="test-001",
            name="Test Job",
            container=ContainerSpec(image="ubuntu:20.04")
        )
        
        assert spec.job_id == "test-001"
        assert spec.name == "Test Job"
        assert spec.container.image == "ubuntu:20.04"
        assert spec.resources.cpus == 1  # Default
        assert spec.input_files == {}
        assert spec.output_files == {}
        assert spec.timeout_seconds is None
        assert spec.retry_attempts == 0
        assert spec.priority == 0
        assert spec.cloud_options == {}
        assert spec.labels == {}
        assert spec.annotations == {}
    
    def test_full_job_spec(self):
        """Test full job specification."""
        spec = JobSpec(
            job_id="full-test-001",
            name="Full Test Job",
            container=ContainerSpec(
                image="python:3.9",
                command=["python"],
                args=["script.py"],
                env={"VAR": "value"}
            ),
            resources=ResourceSpec(
                cpus=4,
                memory_mb=8192,
                gpu=1
            ),
            input_files={
                "/local/input.txt": "input/data.txt"
            },
            output_files={
                "output/result.txt": "/local/result.txt"
            },
            timeout_seconds=3600,
            retry_attempts=3,
            priority=10,
            cloud_options={
                "spot": True,
                "array_size": 10
            },
            labels={
                "project": "test",
                "environment": "dev"
            },
            annotations={
                "description": "Test job for validation"
            }
        )
        
        assert spec.job_id == "full-test-001"
        assert spec.name == "Full Test Job"
        assert spec.container.image == "python:3.9"
        assert spec.resources.cpus == 4
        assert spec.resources.memory_mb == 8192
        assert spec.resources.gpu == 1
        assert spec.input_files["/local/input.txt"] == "input/data.txt"
        assert spec.output_files["output/result.txt"] == "/local/result.txt"
        assert spec.timeout_seconds == 3600
        assert spec.retry_attempts == 3
        assert spec.priority == 10
        assert spec.cloud_options["spot"] is True
        assert spec.cloud_options["array_size"] == 10
        assert spec.labels["project"] == "test"
        assert spec.annotations["description"] == "Test job for validation"
    
    def test_job_spec_validation(self):
        """Test job specification validation."""
        # job_id is required
        with pytest.raises(ValidationError):
            JobSpec(
                name="Test",
                container=ContainerSpec(image="ubuntu:20.04")
            )
        
        # name is required
        with pytest.raises(ValidationError):
            JobSpec(
                job_id="test-001",
                container=ContainerSpec(image="ubuntu:20.04")
            )
        
        # container is required
        with pytest.raises(ValidationError):
            JobSpec(
                job_id="test-001",
                name="Test"
            )
        
        # timeout_seconds must be >= 1 if specified
        with pytest.raises(ValidationError):
            JobSpec(
                job_id="test-001",
                name="Test",
                container=ContainerSpec(image="ubuntu:20.04"),
                timeout_seconds=0
            )
        
        # retry_attempts must be >= 0
        with pytest.raises(ValidationError):
            JobSpec(
                job_id="test-001",
                name="Test",
                container=ContainerSpec(image="ubuntu:20.04"),
                retry_attempts=-1
            )


class TestJobResult:
    """Test JobResult model."""
    
    def test_minimal_job_result(self):
        """Test minimal job result."""
        result = JobResult(
            job_id="test-001",
            status=JobStatus.COMPLETED
        )
        
        assert result.job_id == "test-001"
        assert result.cloud_job_id is None
        assert result.status == JobStatus.COMPLETED
        assert result.submitted_at is None
        assert result.started_at is None
        assert result.finished_at is None
        assert result.exit_code is None
        assert result.stdout is None
        assert result.stderr is None
        assert result.cpu_usage is None
        assert result.memory_usage_mb is None
        assert result.error_message is None
        assert result.error_details == {}
        assert result.cloud_metadata == {}
    
    def test_full_job_result(self):
        """Test full job result."""
        now = datetime.utcnow()
        
        result = JobResult(
            job_id="test-001",
            cloud_job_id="cloud-123",
            status=JobStatus.COMPLETED,
            submitted_at=now,
            started_at=now,
            finished_at=now,
            exit_code=0,
            stdout="Job completed successfully",
            stderr="",
            cpu_usage=2.5,
            memory_usage_mb=1536.0,
            error_message=None,
            error_details={},
            cloud_metadata={
                "instance_type": "m5.large",
                "region": "us-east-1"
            }
        )
        
        assert result.job_id == "test-001"
        assert result.cloud_job_id == "cloud-123"
        assert result.status == JobStatus.COMPLETED
        assert result.submitted_at == now
        assert result.started_at == now
        assert result.finished_at == now
        assert result.exit_code == 0
        assert result.stdout == "Job completed successfully"
        assert result.stderr == ""
        assert result.cpu_usage == 2.5
        assert result.memory_usage_mb == 1536.0
        assert result.cloud_metadata["instance_type"] == "m5.large"
    
    def test_failed_job_result(self):
        """Test failed job result."""
        result = JobResult(
            job_id="failed-001",
            status=JobStatus.FAILED,
            exit_code=1,
            error_message="Job failed due to timeout",
            error_details={
                "error_type": "TimeoutError",
                "timeout_seconds": 3600
            }
        )
        
        assert result.status == JobStatus.FAILED
        assert result.exit_code == 1
        assert result.error_message == "Job failed due to timeout"
        assert result.error_details["error_type"] == "TimeoutError"


class TestJobEvent:
    """Test JobEvent model."""
    
    def test_job_event_creation(self):
        """Test job event creation."""
        event = JobEvent(
            job_id="test-001",
            event_type="status_change",
            message="Job status changed from pending to running",
            details={
                "old_status": "pending",
                "new_status": "running"
            }
        )
        
        assert event.job_id == "test-001"
        assert event.event_type == "status_change"
        assert event.message == "Job status changed from pending to running"
        assert event.details["old_status"] == "pending"
        assert event.details["new_status"] == "running"
        assert isinstance(event.timestamp, datetime)
    
    def test_job_event_defaults(self):
        """Test job event with defaults."""
        event = JobEvent(
            job_id="test-001",
            event_type="log",
            message="Log message"
        )
        
        assert event.job_id == "test-001"
        assert event.event_type == "log"
        assert event.message == "Log message"
        assert event.details == {}
        assert isinstance(event.timestamp, datetime)
    
    def test_job_event_validation(self):
        """Test job event validation."""
        # job_id is required
        with pytest.raises(ValidationError):
            JobEvent(
                event_type="test",
                message="Test message"
            )
        
        # event_type is required
        with pytest.raises(ValidationError):
            JobEvent(
                job_id="test-001",
                message="Test message"
            )
        
        # message is required
        with pytest.raises(ValidationError):
            JobEvent(
                job_id="test-001",
                event_type="test"
            )