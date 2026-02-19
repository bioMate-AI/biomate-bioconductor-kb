"""
AWS Cost Calculator for BioMate

Calculates real-time costs for:
  - AWS Batch compute (CPU and GPU EC2 instances)
  - S3 storage, requests, and data transfer
  - LLM API calls (Claude, etc.)
  - ECR storage

Pricing is based on us-east-1 on-demand rates (update for your region/RI/Spot).
All costs are in USD.
"""

from dataclasses import dataclass, field
from typing import Optional
import math


# ---------------------------------------------------------------------------
# AWS Pricing Tables  (us-east-1, on-demand, 2026-02)
# Update these when AWS changes pricing or when you commit to Reserved/Spot.
# ---------------------------------------------------------------------------

# EC2 instance hourly price (full instance, not per-vCPU)
EC2_INSTANCE_PRICING: dict[str, dict] = {
    # General purpose (CPU jobs)
    "m6i.large":    {"vcpu": 2,  "mem_gb": 8,   "gpu": 0, "price_hr": 0.096},
    "m6i.xlarge":   {"vcpu": 4,  "mem_gb": 16,  "gpu": 0, "price_hr": 0.192},
    "m6i.2xlarge":  {"vcpu": 8,  "mem_gb": 32,  "gpu": 0, "price_hr": 0.384},
    "m6i.4xlarge":  {"vcpu": 16, "mem_gb": 64,  "gpu": 0, "price_hr": 0.768},
    "m6i.8xlarge":  {"vcpu": 32, "mem_gb": 128, "gpu": 0, "price_hr": 1.536},
    # Compute optimised (CPU jobs)
    "c6i.large":    {"vcpu": 2,  "mem_gb": 4,   "gpu": 0, "price_hr": 0.085},
    "c6i.xlarge":   {"vcpu": 4,  "mem_gb": 8,   "gpu": 0, "price_hr": 0.170},
    "c6i.2xlarge":  {"vcpu": 8,  "mem_gb": 16,  "gpu": 0, "price_hr": 0.340},
    "c6i.4xlarge":  {"vcpu": 16, "mem_gb": 32,  "gpu": 0, "price_hr": 0.680},
    "c6i.8xlarge":  {"vcpu": 32, "mem_gb": 64,  "gpu": 0, "price_hr": 1.360},
    # GPU instances
    "g4dn.xlarge":  {"vcpu": 4,  "mem_gb": 16,  "gpu": 1, "price_hr": 0.526},
    "g4dn.2xlarge": {"vcpu": 8,  "mem_gb": 32,  "gpu": 1, "price_hr": 0.752},
    "g4dn.4xlarge": {"vcpu": 16, "mem_gb": 64,  "gpu": 1, "price_hr": 1.204},
    "g4dn.8xlarge": {"vcpu": 32, "mem_gb": 128, "gpu": 1, "price_hr": 2.264},
    "g5.xlarge":    {"vcpu": 4,  "mem_gb": 16,  "gpu": 1, "price_hr": 1.006},
    "g5.2xlarge":   {"vcpu": 8,  "mem_gb": 32,  "gpu": 1, "price_hr": 1.212},
    "g5.4xlarge":   {"vcpu": 16, "mem_gb": 64,  "gpu": 1, "price_hr": 1.624},
    "p3.2xlarge":   {"vcpu": 8,  "mem_gb": 61,  "gpu": 1, "price_hr": 3.060},
    "p4d.24xlarge": {"vcpu": 96, "mem_gb": 1152,"gpu": 8, "price_hr": 32.77},
}

# Fallback per-resource pricing when instance type is unknown
# (used when AWS Batch Fargate compute environment is used)
FARGATE_VCPU_PRICE_HR  = 0.04048   # $/vCPU-hour
FARGATE_MEM_GB_PRICE_HR = 0.004445  # $/GB-hour

# Derived per-vCPU and per-GB rates for EC2 (used for partial-job attribution).
# When a single EC2 instance runs ONE job the full instance cost is charged.
# When an instance runs MULTIPLE jobs, costs are split by vCPU/memory share.
# BioMate runs one job per container → use full instance price for now.

# S3 pricing (us-east-1)
S3_STORAGE_STANDARD_PER_GB_MONTH = 0.023
S3_STORAGE_IA_PER_GB_MONTH       = 0.0125
S3_STORAGE_GLACIER_PER_GB_MONTH  = 0.004
S3_PUT_PER_1K_REQUESTS           = 0.005   # PUT, COPY, POST, LIST
S3_GET_PER_1K_REQUESTS           = 0.0004  # GET, SELECT, all others
S3_DATA_OUT_PER_GB               = 0.09    # first 10 TB/month; in-region free
S3_DATA_IN_PER_GB                = 0.00    # ingress always free

# ECR pricing
ECR_STORAGE_PER_GB_MONTH         = 0.10

# LLM API pricing (per 1M tokens)
LLM_PRICING: dict[str, dict] = {
    # Anthropic Claude
    "claude-opus-4-6":                {"input_per_1m": 15.00, "output_per_1m": 75.00},
    "claude-sonnet-4-5-20250929":     {"input_per_1m":  3.00, "output_per_1m": 15.00},
    "claude-haiku-4-5-20251001":      {"input_per_1m":  0.25, "output_per_1m":  1.25},
    # Fallback
    "default":                        {"input_per_1m":  3.00, "output_per_1m": 15.00},
}


# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------

@dataclass
class BatchJobCost:
    job_id: str
    user_id: str
    workflow_id: str
    instance_type: str
    vcpus: float
    memory_gb: float
    gpu_count: int
    duration_seconds: float
    is_spot: bool

    # Calculated fields
    vcpu_cost: float = 0.0
    memory_cost: float = 0.0
    gpu_cost: float = 0.0
    total_cost: float = 0.0

    def __post_init__(self):
        self.total_cost = self.vcpu_cost + self.memory_cost + self.gpu_cost


@dataclass
class S3OperationCost:
    user_id: str
    bucket: str
    operation: str          # PUT | GET | DELETE | LIST
    bytes_transferred: int
    storage_class: str = "STANDARD"

    storage_cost: float = 0.0
    request_cost: float = 0.0
    transfer_cost: float = 0.0
    total_cost: float = 0.0


@dataclass
class LLMCallCost:
    user_id: str
    session_id: str
    model: str
    input_tokens: int
    output_tokens: int

    input_cost: float = 0.0
    output_cost: float = 0.0
    total_cost: float = 0.0


# ---------------------------------------------------------------------------
# Calculator
# ---------------------------------------------------------------------------

class CostCalculator:
    """
    Pure-function cost calculator.  No I/O — takes raw numbers, returns costs.
    All monetary values are USD.
    """

    # ---- AWS Batch --------------------------------------------------------

    def batch_job_cost(
        self,
        job_id: str,
        user_id: str,
        workflow_id: str,
        instance_type: str,
        vcpus: float,
        memory_mb: int,
        gpu_count: int,
        duration_seconds: float,
        is_spot: bool = False,
        spot_discount: float = 0.65,  # typical Spot savings
    ) -> BatchJobCost:
        """
        Calculate cost for a completed (or estimated running) AWS Batch job.

        For EC2 launch type: derive per-vCPU and per-GB prices from the
        full instance price so that partial allocations are correctly attributed.
        For Fargate launch type: use Fargate rates directly.
        """
        # Security: Clamp negative values to zero to prevent credit exploits
        duration_seconds = max(0, duration_seconds)
        spot_discount = max(0, min(1.0, spot_discount))  # Clamp to [0, 1]

        hours = duration_seconds / 3600.0
        memory_gb = memory_mb / 1024.0

        if instance_type == "FARGATE" or instance_type not in EC2_INSTANCE_PRICING:
            # Fargate or unknown instance → per-resource pricing
            vcpu_cost   = vcpus * hours * FARGATE_VCPU_PRICE_HR
            memory_cost = memory_gb * hours * FARGATE_MEM_GB_PRICE_HR
            gpu_cost    = 0.0  # Fargate does not support GPU
        else:
            spec = EC2_INSTANCE_PRICING[instance_type]
            full_hr = spec["price_hr"]
            total_vcpu = spec["vcpu"]
            total_mem  = spec["mem_gb"]
            total_gpu  = max(spec["gpu"], 1)  # avoid div/0

            # Charge by max(vcpu_share, mem_share) to avoid double-counting
            # when job doesn't fill the instance in both dimensions.
            vcpu_share    = vcpus / total_vcpu
            mem_share     = memory_gb / total_mem
            compute_share = max(vcpu_share, mem_share)

            # Distribute the attributed instance cost across the three
            # cost dimensions so they sum exactly to 100 %.
            base = full_hr * hours * compute_share
            if gpu_count > 0:
                vcpu_cost   = base * 0.50
                memory_cost = base * 0.30
                gpu_cost    = base * 0.20
            else:
                vcpu_cost   = base * 0.60
                memory_cost = base * 0.40
                gpu_cost    = 0.0

        if is_spot:
            factor = 1.0 - spot_discount
            vcpu_cost   *= factor
            memory_cost *= factor
            gpu_cost    *= factor

        return BatchJobCost(
            job_id=job_id,
            user_id=user_id,
            workflow_id=workflow_id,
            instance_type=instance_type,
            vcpus=vcpus,
            memory_gb=memory_gb,
            gpu_count=gpu_count,
            duration_seconds=duration_seconds,
            is_spot=is_spot,
            vcpu_cost=round(vcpu_cost, 8),
            memory_cost=round(memory_cost, 8),
            gpu_cost=round(gpu_cost, 8),
            total_cost=round(vcpu_cost + memory_cost + gpu_cost, 8),
        )

    def estimate_running_job_cost(
        self,
        instance_type: str,
        vcpus: float,
        memory_mb: int,
        gpu_count: int,
        started_at_ms: int,      # Unix ms
        now_ms: int,
        is_spot: bool = False,
    ) -> float:
        """
        Returns estimated cost so far for a RUNNING job.
        Called every N seconds to update the real-time dashboard.
        """
        elapsed_seconds = max(0, (now_ms - started_at_ms) / 1000.0)
        cost = self.batch_job_cost(
            job_id="running",
            user_id="",
            workflow_id="",
            instance_type=instance_type,
            vcpus=vcpus,
            memory_mb=memory_mb,
            gpu_count=gpu_count,
            duration_seconds=elapsed_seconds,
            is_spot=is_spot,
        )
        return cost.total_cost

    # ---- S3 ---------------------------------------------------------------

    def s3_put_cost(
        self,
        user_id: str,
        bucket: str,
        size_bytes: int,
        storage_class: str = "STANDARD",
    ) -> S3OperationCost:
        """Cost for uploading one object to S3."""
        gb = size_bytes / (1024 ** 3)

        # Storage cost: amortised for 30-day retention (configurable)
        storage_per_gb = {
            "STANDARD":           S3_STORAGE_STANDARD_PER_GB_MONTH,
            "STANDARD_IA":        S3_STORAGE_IA_PER_GB_MONTH,
            "GLACIER":            S3_STORAGE_GLACIER_PER_GB_MONTH,
        }.get(storage_class, S3_STORAGE_STANDARD_PER_GB_MONTH)

        storage_cost  = gb * storage_per_gb  # per month; actual cost spread over retention
        request_cost  = S3_PUT_PER_1K_REQUESTS / 1000.0  # 1 PUT request
        transfer_cost = 0.0  # inbound is free

        return S3OperationCost(
            user_id=user_id,
            bucket=bucket,
            operation="PUT",
            bytes_transferred=size_bytes,
            storage_class=storage_class,
            storage_cost=round(storage_cost, 8),
            request_cost=round(request_cost, 8),
            transfer_cost=transfer_cost,
            total_cost=round(storage_cost + request_cost, 8),
        )

    def s3_get_cost(
        self,
        user_id: str,
        bucket: str,
        size_bytes: int,
        is_cross_region: bool = False,
    ) -> S3OperationCost:
        """Cost for downloading one object from S3."""
        gb = size_bytes / (1024 ** 3)
        transfer_cost = gb * S3_DATA_OUT_PER_GB if is_cross_region else 0.0
        request_cost  = S3_GET_PER_1K_REQUESTS / 1000.0

        return S3OperationCost(
            user_id=user_id,
            bucket=bucket,
            operation="GET",
            bytes_transferred=size_bytes,
            request_cost=round(request_cost, 8),
            transfer_cost=round(transfer_cost, 8),
            total_cost=round(request_cost + transfer_cost, 8),
        )

    def s3_monthly_storage_cost(self, size_gb: float, storage_class: str = "STANDARD") -> float:
        rate = {
            "STANDARD":    S3_STORAGE_STANDARD_PER_GB_MONTH,
            "STANDARD_IA": S3_STORAGE_IA_PER_GB_MONTH,
            "GLACIER":     S3_STORAGE_GLACIER_PER_GB_MONTH,
        }.get(storage_class, S3_STORAGE_STANDARD_PER_GB_MONTH)
        return round(size_gb * rate, 8)

    # ---- LLM --------------------------------------------------------------

    def llm_call_cost(
        self,
        user_id: str,
        session_id: str,
        model: str,
        input_tokens: int,
        output_tokens: int,
    ) -> LLMCallCost:
        # Security: Clamp negative token counts to zero to prevent credit exploits
        input_tokens = max(0, input_tokens)
        output_tokens = max(0, output_tokens)

        pricing = LLM_PRICING.get(model, LLM_PRICING["default"])
        input_cost  = (input_tokens  / 1_000_000) * pricing["input_per_1m"]
        output_cost = (output_tokens / 1_000_000) * pricing["output_per_1m"]
        return LLMCallCost(
            user_id=user_id,
            session_id=session_id,
            model=model,
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            input_cost=round(input_cost, 8),
            output_cost=round(output_cost, 8),
            total_cost=round(input_cost + output_cost, 8),
        )
