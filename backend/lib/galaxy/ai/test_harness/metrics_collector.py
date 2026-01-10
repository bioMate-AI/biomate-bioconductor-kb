"""
Metrics Collector

Collects performance and quality metrics during benchmark runs.
"""

import logging
import os
import time
import subprocess
from typing import Dict, List, Any, Optional
from dataclasses import dataclass, field, asdict
from pathlib import Path

log = logging.getLogger(__name__)


@dataclass
class MemoryProfile:
    """Memory usage profile."""
    peak_gb: float
    average_gb: float
    samples: List[float] = field(default_factory=list)

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass
class ResourceUsage:
    """Resource usage during execution."""
    cpu_percent: float
    memory_gb: float
    io_read_mb: float
    io_write_mb: float
    duration_seconds: float

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass
class QualityMetrics:
    """Quality metrics for tool output."""
    # Generic metrics
    output_file_count: int = 0
    output_total_size_mb: float = 0.0

    # Alignment-specific
    alignment_rate: Optional[float] = None
    multi_mapping_rate: Optional[float] = None
    uniquely_mapped_rate: Optional[float] = None

    # Variant-specific
    variant_count: Optional[int] = None
    ti_tv_ratio: Optional[float] = None

    # Expression-specific
    genes_detected: Optional[int] = None
    median_coverage: Optional[float] = None

    # Custom metrics
    custom: Dict[str, float] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        result = asdict(self)
        # Remove None values
        return {k: v for k, v in result.items() if v is not None}


@dataclass
class JobMetrics:
    """Complete metrics for a job execution."""
    job_id: str
    tool_id: str

    # Timing
    runtime_seconds: float
    start_time: str
    end_time: str

    # Resources
    peak_memory_gb: float
    cpu_utilization: float

    # Quality
    quality: QualityMetrics = field(default_factory=QualityMetrics)

    # Status
    success: bool = True
    error_message: Optional[str] = None

    def to_dict(self) -> Dict[str, Any]:
        return {
            "job_id": self.job_id,
            "tool_id": self.tool_id,
            "runtime_seconds": self.runtime_seconds,
            "start_time": self.start_time,
            "end_time": self.end_time,
            "peak_memory_gb": self.peak_memory_gb,
            "cpu_utilization": self.cpu_utilization,
            "quality": self.quality.to_dict(),
            "success": self.success,
            "error_message": self.error_message
        }


class MetricsCollector:
    """
    Collects performance and quality metrics during benchmark runs.

    Features:
    - Runtime measurement
    - Memory profiling
    - CPU utilization tracking
    - Output quality assessment
    - Tool-specific metric extraction
    """

    def __init__(self):
        self._active_jobs: Dict[str, Dict[str, Any]] = {}

    def start_collection(self, job_id: str, tool_id: str):
        """Start collecting metrics for a job."""
        self._active_jobs[job_id] = {
            "tool_id": tool_id,
            "start_time": time.time(),
            "memory_samples": [],
            "cpu_samples": []
        }
        log.debug(f"Started metrics collection for job {job_id}")

    def sample_resources(self, job_id: str, pid: int = None):
        """Sample current resource usage."""
        if job_id not in self._active_jobs:
            return

        job = self._active_jobs[job_id]

        try:
            # Get memory and CPU usage
            if pid:
                memory_gb, cpu_percent = self._get_process_resources(pid)
            else:
                memory_gb, cpu_percent = self._get_system_resources()

            job["memory_samples"].append(memory_gb)
            job["cpu_samples"].append(cpu_percent)

        except Exception as e:
            log.debug(f"Failed to sample resources: {e}")

    def _get_process_resources(self, pid: int) -> tuple:
        """Get resource usage for a specific process."""
        try:
            import psutil
            process = psutil.Process(pid)
            memory_gb = process.memory_info().rss / (1024 ** 3)
            cpu_percent = process.cpu_percent()
            return memory_gb, cpu_percent
        except ImportError:
            return 0.0, 0.0
        except Exception as e:
            # Catches psutil.NoSuchProcess, psutil.AccessDenied, and other OS errors
            log.debug(f"Failed to get process resources for pid {pid}: {e}")
            return 0.0, 0.0

    def _get_system_resources(self) -> tuple:
        """Get system-wide resource usage."""
        try:
            import psutil
            memory = psutil.virtual_memory()
            memory_gb = memory.used / (1024 ** 3)
            cpu_percent = psutil.cpu_percent()
            return memory_gb, cpu_percent
        except ImportError:
            return 0.0, 0.0
        except Exception as e:
            log.debug(f"Failed to get system resources: {e}")
            return 0.0, 0.0

    def stop_collection(self, job_id: str) -> JobMetrics:
        """Stop collecting and return metrics."""
        if job_id not in self._active_jobs:
            raise ValueError(f"Unknown job: {job_id}")

        job = self._active_jobs[job_id]
        end_time = time.time()

        runtime = end_time - job["start_time"]

        # Calculate memory stats
        memory_samples = job.get("memory_samples", [0])
        peak_memory = max(memory_samples) if memory_samples else 0

        # Calculate CPU stats
        cpu_samples = job.get("cpu_samples", [0])
        avg_cpu = sum(cpu_samples) / len(cpu_samples) if cpu_samples else 0

        from datetime import datetime
        metrics = JobMetrics(
            job_id=job_id,
            tool_id=job["tool_id"],
            runtime_seconds=runtime,
            start_time=datetime.fromtimestamp(job["start_time"]).isoformat(),
            end_time=datetime.fromtimestamp(end_time).isoformat(),
            peak_memory_gb=peak_memory,
            cpu_utilization=avg_cpu
        )

        del self._active_jobs[job_id]
        log.debug(f"Stopped metrics collection for job {job_id}: {runtime:.2f}s")

        return metrics

    def collect_runtime(self, job_id: str) -> float:
        """Get job runtime in seconds."""
        if job_id in self._active_jobs:
            return time.time() - self._active_jobs[job_id]["start_time"]
        return 0.0

    def collect_memory(self, job_id: str) -> MemoryProfile:
        """Get memory usage profile."""
        if job_id not in self._active_jobs:
            return MemoryProfile(peak_gb=0, average_gb=0)

        samples = self._active_jobs[job_id].get("memory_samples", [])
        if not samples:
            return MemoryProfile(peak_gb=0, average_gb=0)

        return MemoryProfile(
            peak_gb=max(samples),
            average_gb=sum(samples) / len(samples),
            samples=samples
        )

    def collect_output_quality(
        self,
        output_dir: str,
        tool_id: str,
        ground_truth: Optional[str] = None
    ) -> QualityMetrics:
        """
        Assess output quality based on tool type.

        Args:
            output_dir: Directory containing output files
            tool_id: Tool identifier for tool-specific parsing
            ground_truth: Optional ground truth for comparison

        Returns:
            QualityMetrics with tool-specific metrics
        """
        quality = QualityMetrics()

        output_path = Path(output_dir)
        if not output_path.exists():
            return quality

        # Count files and total size
        files = list(output_path.rglob("*"))
        quality.output_file_count = len([f for f in files if f.is_file()])
        quality.output_total_size_mb = sum(
            f.stat().st_size for f in files if f.is_file()
        ) / (1024 * 1024)

        # Tool-specific quality extraction
        tool_lower = tool_id.lower()

        if "star" in tool_lower:
            quality = self._extract_star_metrics(output_path, quality)
        elif "hisat" in tool_lower:
            quality = self._extract_hisat_metrics(output_path, quality)
        elif "salmon" in tool_lower or "kallisto" in tool_lower:
            quality = self._extract_quant_metrics(output_path, quality)
        elif "gatk" in tool_lower or "freebayes" in tool_lower:
            quality = self._extract_variant_metrics(output_path, quality)
        elif "featurecounts" in tool_lower or "htseq" in tool_lower:
            quality = self._extract_count_metrics(output_path, quality)

        return quality

    def _extract_star_metrics(self, output_dir: Path, quality: QualityMetrics) -> QualityMetrics:
        """Extract metrics from STAR output."""
        # Look for Log.final.out
        log_file = output_dir / "Log.final.out"
        if not log_file.exists():
            log_files = list(output_dir.glob("**/Log.final.out"))
            if log_files:
                log_file = log_files[0]

        if log_file.exists():
            try:
                content = log_file.read_text()
                for line in content.split("\n"):
                    if "Uniquely mapped reads %" in line:
                        quality.uniquely_mapped_rate = float(line.split("|")[-1].strip().rstrip("%")) / 100
                    elif "% of reads mapped to multiple loci" in line:
                        quality.multi_mapping_rate = float(line.split("|")[-1].strip().rstrip("%")) / 100
            except Exception as e:
                log.debug(f"Failed to parse STAR log: {e}")

        if quality.uniquely_mapped_rate is not None:
            quality.alignment_rate = quality.uniquely_mapped_rate
            if quality.multi_mapping_rate:
                quality.alignment_rate += quality.multi_mapping_rate

        return quality

    def _extract_hisat_metrics(self, output_dir: Path, quality: QualityMetrics) -> QualityMetrics:
        """Extract metrics from HISAT2 output."""
        # Look for alignment summary
        for log_file in output_dir.glob("**/*.log"):
            try:
                content = log_file.read_text()
                for line in content.split("\n"):
                    if "overall alignment rate" in line.lower():
                        rate_str = line.split()[0].rstrip("%")
                        quality.alignment_rate = float(rate_str) / 100
                        break
            except (IOError, OSError, ValueError, IndexError) as e:
                log.debug(f"Failed to parse HISAT2 log {log_file}: {e}")

        return quality

    def _extract_quant_metrics(self, output_dir: Path, quality: QualityMetrics) -> QualityMetrics:
        """Extract metrics from quantification output (Salmon/Kallisto)."""
        # Look for meta_info.json or run_info.json
        for json_file in output_dir.glob("**/*info*.json"):
            try:
                import json
                data = json.loads(json_file.read_text())
                if "percent_mapped" in data:
                    quality.alignment_rate = data["percent_mapped"] / 100
                if "num_processed" in data:
                    quality.custom["reads_processed"] = data["num_processed"]
            except (IOError, OSError, json.JSONDecodeError, KeyError, TypeError) as e:
                log.debug(f"Failed to parse quant info file {json_file}: {e}")

        # Count detected genes from quant.sf
        for quant_file in output_dir.glob("**/quant.sf"):
            try:
                detected = 0
                with open(quant_file) as f:
                    next(f)  # Skip header
                    for line in f:
                        parts = line.strip().split("\t")
                        if len(parts) >= 4 and float(parts[3]) > 0:
                            detected += 1
                quality.genes_detected = detected
            except (IOError, OSError, ValueError, IndexError, StopIteration) as e:
                log.debug(f"Failed to parse quant file {quant_file}: {e}")

        return quality

    def _extract_variant_metrics(self, output_dir: Path, quality: QualityMetrics) -> QualityMetrics:
        """Extract metrics from variant calling output."""
        # Count variants in VCF
        for vcf_file in output_dir.glob("**/*.vcf*"):
            try:
                variant_count = 0
                transitions = 0
                transversions = 0

                import gzip
                opener = gzip.open if str(vcf_file).endswith(".gz") else open

                with opener(vcf_file, "rt") as f:
                    for line in f:
                        if line.startswith("#"):
                            continue
                        variant_count += 1

                        # Calculate Ti/Tv
                        parts = line.split("\t")
                        if len(parts) >= 5:
                            ref, alt = parts[3], parts[4]
                            if len(ref) == 1 and len(alt) == 1:
                                if (ref in "AG" and alt in "AG") or (ref in "CT" and alt in "CT"):
                                    transitions += 1
                                else:
                                    transversions += 1

                quality.variant_count = variant_count
                if transversions > 0:
                    quality.ti_tv_ratio = transitions / transversions

            except Exception as e:
                log.debug(f"Failed to parse VCF: {e}")

        return quality

    def _extract_count_metrics(self, output_dir: Path, quality: QualityMetrics) -> QualityMetrics:
        """Extract metrics from read counting output."""
        # Look for count files
        for count_file in output_dir.glob("**/*counts*"):
            try:
                detected = 0
                with open(count_file) as f:
                    for line in f:
                        if line.startswith("#") or line.startswith("__"):
                            continue
                        parts = line.strip().split("\t")
                        if len(parts) >= 2:
                            count = int(parts[-1])
                            if count > 0:
                                detected += 1
                quality.genes_detected = detected
            except (IOError, OSError, ValueError, IndexError) as e:
                log.debug(f"Failed to parse count file {count_file}: {e}")

        return quality

    def collect_resource_usage(self, job_id: str) -> ResourceUsage:
        """Get comprehensive resource usage for a job."""
        if job_id not in self._active_jobs:
            return ResourceUsage(
                cpu_percent=0, memory_gb=0, io_read_mb=0, io_write_mb=0, duration_seconds=0
            )

        job = self._active_jobs[job_id]
        duration = time.time() - job["start_time"]

        cpu_samples = job.get("cpu_samples", [0])
        memory_samples = job.get("memory_samples", [0])

        return ResourceUsage(
            cpu_percent=sum(cpu_samples) / len(cpu_samples) if cpu_samples else 0,
            memory_gb=max(memory_samples) if memory_samples else 0,
            io_read_mb=0,  # Would need process-specific tracking
            io_write_mb=0,
            duration_seconds=duration
        )


class MetricsTimer:
    """Context manager for timing operations."""

    def __init__(self, collector: MetricsCollector, job_id: str, tool_id: str):
        self.collector = collector
        self.job_id = job_id
        self.tool_id = tool_id
        self.metrics: Optional[JobMetrics] = None

    def __enter__(self):
        self.collector.start_collection(self.job_id, self.tool_id)
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.metrics = self.collector.stop_collection(self.job_id)
        if exc_type:
            self.metrics.success = False
            self.metrics.error_message = str(exc_val)
        return False

    def sample(self, pid: int = None):
        """Take a resource sample."""
        self.collector.sample_resources(self.job_id, pid)
