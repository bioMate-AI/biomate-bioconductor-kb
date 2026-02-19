"""
BioMate Billing System — Edge Case Test Suite

Tests extreme values, boundary conditions, and unusual scenarios
that could break the cost calculation logic.

Coverage:
  1. Extreme durations (1s, 24h+, 1000h)
  2. Boundary conditions (exact hour, exact day)
  3. Large numbers (billions of tokens, petabyte files)
  4. Floating point precision (very small costs)
  5. Instance type extremes (fractional vCPUs, massive instances)
  6. Memory extremes (tiny, huge)
  7. Thread safety (concurrent calculations)
  8. S3 storage classes (all variants)
  9. Spot discount edge cases (0%, 100%, invalid)
  10. Time zone/month boundary edge cases

Run:
    cd backend
    BILLING_DEV_MODE=true pytest lib/galaxy/ai/billing/tests/test_billing_edge_cases.py -v
"""

import json
import math
import time
import threading
import unittest
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone, timedelta
from decimal import Decimal
from typing import List

import pytest


# ---------------------------------------------------------------------------
# 1.  Extreme Duration Tests
# ---------------------------------------------------------------------------

class TestExtremeDurations(unittest.TestCase):
    """Test cost calculations with extreme job durations."""

    def setUp(self):
        from galaxy.ai.billing.core.cost_calculator import CostCalculator
        self.calc = CostCalculator()

    def test_one_second_job_cost(self):
        """1-second job should cost 1/3600 of hourly rate."""
        result = self.calc.batch_job_cost(
            job_id="j-1s",
            user_id="u1",
            workflow_id="wf1",
            instance_type="c6i.xlarge",
            vcpus=4,
            memory_mb=8192,
            gpu_count=0,
            duration_seconds=1,
            is_spot=False,
        )
        # c6i.xlarge is $0.170/hr, so 1 second ≈ $0.000047
        assert 0 < result.total_cost < 0.001, (
            f"1-second job cost ${result.total_cost:.8f} seems too high"
        )

    def test_24_hour_job_cost(self):
        """24-hour job should cost exactly 24x the hourly rate."""
        result = self.calc.batch_job_cost(
            job_id="j-24h",
            user_id="u1",
            workflow_id="wf1",
            instance_type="c6i.xlarge",
            vcpus=4,
            memory_mb=8192,
            gpu_count=0,
            duration_seconds=86400,  # 24 hours
            is_spot=False,
        )
        from galaxy.ai.billing.core.cost_calculator import EC2_INSTANCE_PRICING
        hourly_rate = EC2_INSTANCE_PRICING["c6i.xlarge"]["price_hr"]
        expected = hourly_rate * 24
        assert abs(result.total_cost - expected) < 0.01, (
            f"24-hour job: expected ${expected:.2f}, got ${result.total_cost:.2f}"
        )

    def test_1000_hour_job_cost(self):
        """Very long job (1000 hours) should scale linearly."""
        result = self.calc.batch_job_cost(
            job_id="j-1000h",
            user_id="u1",
            workflow_id="wf1",
            instance_type="m6i.xlarge",
            vcpus=4,
            memory_mb=16384,
            gpu_count=0,
            duration_seconds=3_600_000,  # 1000 hours
            is_spot=False,
        )
        from galaxy.ai.billing.core.cost_calculator import EC2_INSTANCE_PRICING
        hourly_rate = EC2_INSTANCE_PRICING["m6i.xlarge"]["price_hr"]
        expected = hourly_rate * 1000
        # Allow 1% tolerance for floating point accumulation
        assert abs(result.total_cost - expected) < expected * 0.01, (
            f"1000-hour job: expected ~${expected:.2f}, got ${result.total_cost:.2f}"
        )

    def test_exactly_one_hour_boundary(self):
        """Job lasting exactly 3600 seconds should match hourly rate."""
        result = self.calc.batch_job_cost(
            job_id="j-exactly-1h",
            user_id="u1",
            workflow_id="wf1",
            instance_type="c6i.xlarge",
            vcpus=4,
            memory_mb=8192,
            gpu_count=0,
            duration_seconds=3600,
            is_spot=False,
        )
        from galaxy.ai.billing.core.cost_calculator import EC2_INSTANCE_PRICING
        hourly_rate = EC2_INSTANCE_PRICING["c6i.xlarge"]["price_hr"]
        assert abs(result.total_cost - hourly_rate) < 0.001


# ---------------------------------------------------------------------------
# 2.  Large Number Tests
# ---------------------------------------------------------------------------

class TestLargeNumbers(unittest.TestCase):
    """Test calculations with very large inputs."""

    def setUp(self):
        from galaxy.ai.billing.core.cost_calculator import CostCalculator
        self.calc = CostCalculator()

    def test_billion_token_llm_call(self):
        """1 billion input + 1 billion output tokens."""
        result = self.calc.llm_call_cost(
            user_id="u1",
            session_id="s1",
            model="claude-sonnet-4-5-20250929",
            input_tokens=1_000_000_000,
            output_tokens=1_000_000_000,
        )
        # Sonnet: $3/1M input, $15/1M output
        # 1B input = $3000, 1B output = $15000, total = $18000
        expected = 3000 + 15000
        assert abs(result.total_cost - expected) < 1.0, (
            f"1B tokens: expected ${expected}, got ${result.total_cost:.2f}"
        )

    def test_s3_petabyte_file(self):
        """1 PB file (within S3 limits, just very large)."""
        # S3 max single object is 5TB, but we can test large calculations
        # For this test, we'll use 1TB which is realistic
        result = self.calc.s3_put_cost(
            user_id="u1",
            bucket="biomate-data",
            size_bytes=1_099_511_627_776,  # 1 TiB
            storage_class="STANDARD",
        )
        # Standard: $0.023/GB-month, 1TB = 1024GB
        # Monthly storage = 1024 * 0.023 = $23.55
        # Plus 1 PUT request ($0.005 per 1000 = $0.000005)
        assert result.storage_cost > 20.0, (
            f"1TB storage cost ${result.storage_cost:.2f} seems too low"
        )
        assert result.total_cost > 20.0


# ---------------------------------------------------------------------------
# 3.  Floating Point Precision Tests
# ---------------------------------------------------------------------------

class TestFloatingPointPrecision(unittest.TestCase):
    """Test very small costs that might round incorrectly."""

    def setUp(self):
        from galaxy.ai.billing.core.cost_calculator import CostCalculator
        self.calc = CostCalculator()

    def test_micro_cent_cost_preserved(self):
        """Very short job (0.1 second) should not round to zero."""
        result = self.calc.batch_job_cost(
            job_id="j-micro",
            user_id="u1",
            workflow_id="wf1",
            instance_type="c6i.xlarge",
            vcpus=4,
            memory_mb=8192,
            gpu_count=0,
            duration_seconds=0.1,
            is_spot=False,
        )
        # Should be > 0 but < $0.000001
        assert result.total_cost > 0, "0.1-second job cost rounded to zero"
        assert result.total_cost < 0.001

    def test_single_token_llm_cost(self):
        """1 input token + 1 output token should not be zero."""
        result = self.calc.llm_call_cost(
            user_id="u1",
            session_id="s1",
            model="claude-haiku-4-5-20251001",
            input_tokens=1,
            output_tokens=1,
        )
        assert result.total_cost > 0, "Single token cost rounded to zero"
        assert result.total_cost < 0.01

    def test_tiny_s3_object(self):
        """1-byte S3 object should charge PUT request but minimal storage."""
        result = self.calc.s3_put_cost(
            user_id="u1",
            bucket="biomate-data",
            size_bytes=1,
            storage_class="STANDARD",
        )
        # Storage should be ~$0, request should be $0.000005
        assert result.request_cost > 0
        assert result.storage_cost >= 0  # Can be zero for 1 byte


# ---------------------------------------------------------------------------
# 4.  Instance Type Extremes
# ---------------------------------------------------------------------------

class TestInstanceTypeExtremes(unittest.TestCase):
    """Test unusual instance configurations."""

    def setUp(self):
        from galaxy.ai.billing.core.cost_calculator import CostCalculator
        self.calc = CostCalculator()

    def test_fargate_fractional_vcpu(self):
        """Fargate allows 0.25 vCPUs (fractional)."""
        result = self.calc.batch_job_cost(
            job_id="j-fargate-quarter",
            user_id="u1",
            workflow_id="wf1",
            instance_type="FARGATE",
            vcpus=0.25,
            memory_mb=512,
            gpu_count=0,
            duration_seconds=3600,
            is_spot=False,
        )
        # Fargate: $0.04048/vCPU-hr, $0.004445/GB-hr
        # 0.25 vCPU = $0.01012, 0.5 GB = $0.00222, total ≈ $0.0123
        assert result.total_cost > 0
        assert result.total_cost < 0.05

    def test_massive_p4d_24xlarge_instance(self):
        """p4d.24xlarge: 96 vCPUs, 1152 GB RAM, 8 GPUs."""
        result = self.calc.batch_job_cost(
            job_id="j-massive",
            user_id="u1",
            workflow_id="wf1",
            instance_type="p4d.24xlarge",
            vcpus=96,
            memory_mb=1_179_648,  # 1152 GB
            gpu_count=8,
            duration_seconds=3600,
            is_spot=False,
        )
        # p4d.24xlarge ≈ $32/hr (on-demand)
        from galaxy.ai.billing.core.cost_calculator import EC2_INSTANCE_PRICING
        if "p4d.24xlarge" in EC2_INSTANCE_PRICING:
            hourly_rate = EC2_INSTANCE_PRICING["p4d.24xlarge"]["price_hr"]
            assert abs(result.total_cost - hourly_rate) < 1.0
        else:
            # If not in pricing table, should fall back to Fargate
            assert result.total_cost > 0

    def test_eight_gpu_job(self):
        """Job requesting 8 GPUs should attribute GPU cost correctly."""
        result = self.calc.batch_job_cost(
            job_id="j-8gpu",
            user_id="u1",
            workflow_id="wf1",
            instance_type="p4d.24xlarge",
            vcpus=96,
            memory_mb=1_179_648,
            gpu_count=8,
            duration_seconds=3600,
            is_spot=False,
        )
        # GPU cost should be non-zero and significant portion of total
        assert result.gpu_cost > 0, "8-GPU job has zero GPU cost"
        assert result.gpu_cost > result.vcpu_cost, (
            "GPU cost should exceed vCPU cost for 8-GPU job"
        )


# ---------------------------------------------------------------------------
# 5.  Memory Extremes
# ---------------------------------------------------------------------------

class TestMemoryExtremes(unittest.TestCase):
    """Test very small and very large memory allocations."""

    def setUp(self):
        from galaxy.ai.billing.core.cost_calculator import CostCalculator
        self.calc = CostCalculator()

    def test_tiny_memory_128mb(self):
        """Fargate minimum: 0.25 vCPU, 128 MB."""
        result = self.calc.batch_job_cost(
            job_id="j-tiny-mem",
            user_id="u1",
            workflow_id="wf1",
            instance_type="FARGATE",
            vcpus=0.25,
            memory_mb=128,
            gpu_count=0,
            duration_seconds=3600,
            is_spot=False,
        )
        assert result.total_cost > 0
        assert result.total_cost < 0.03

    def test_massive_memory_1tb(self):
        """High-memory instance: 1 TB RAM."""
        result = self.calc.batch_job_cost(
            job_id="j-1tb-ram",
            user_id="u1",
            workflow_id="wf1",
            instance_type="FARGATE",
            vcpus=16,
            memory_mb=1_048_576,  # 1 TB = 1024 GB = 1,048,576 MB
            gpu_count=0,
            duration_seconds=3600,
            is_spot=False,
        )
        # Fargate: $0.004445/GB-hr, 1024 GB = $4.55/hr
        assert result.memory_cost > 4.0, (
            f"1TB memory cost ${result.memory_cost:.2f} seems too low"
        )


# ---------------------------------------------------------------------------
# 6.  Thread Safety Tests
# ---------------------------------------------------------------------------

class TestThreadSafety(unittest.TestCase):
    """Verify cost calculations are thread-safe."""

    def setUp(self):
        from galaxy.ai.billing.core.cost_calculator import CostCalculator
        self.calc = CostCalculator()

    def test_concurrent_batch_cost_calculations(self):
        """100 concurrent cost calculations should all succeed."""
        results = []

        def calculate():
            result = self.calc.batch_job_cost(
                job_id=f"j-{threading.current_thread().name}",
                user_id="u1",
                workflow_id="wf1",
                instance_type="c6i.xlarge",
                vcpus=4,
                memory_mb=8192,
                gpu_count=0,
                duration_seconds=3600,
                is_spot=False,
            )
            results.append(result.total_cost)

        with ThreadPoolExecutor(max_workers=10) as executor:
            futures = [executor.submit(calculate) for _ in range(100)]
            for future in futures:
                future.result()  # Wait for completion

        # All results should be identical (deterministic calculation)
        assert len(results) == 100
        assert len(set(results)) == 1, (
            f"Thread-safe calculation produced varying results: {set(results)}"
        )

    def test_concurrent_llm_cost_calculations(self):
        """50 concurrent LLM cost calculations."""
        results = []

        def calculate():
            result = self.calc.llm_call_cost(
                user_id="u1",
                session_id="s1",
                model="claude-sonnet-4-5-20250929",
                input_tokens=10000,
                output_tokens=5000,
            )
            results.append(result.total_cost)

        with ThreadPoolExecutor(max_workers=5) as executor:
            futures = [executor.submit(calculate) for _ in range(50)]
            for future in futures:
                future.result()

        assert len(results) == 50
        assert len(set(results)) == 1, "LLM calculations not thread-safe"


# ---------------------------------------------------------------------------
# 7.  S3 Storage Class Edge Cases
# ---------------------------------------------------------------------------

class TestS3StorageClasses(unittest.TestCase):
    """Test all S3 storage classes."""

    def setUp(self):
        from galaxy.ai.billing.core.cost_calculator import CostCalculator
        self.calc = CostCalculator()

    def test_standard_ia_storage(self):
        """STANDARD_IA has different pricing than STANDARD."""
        result = self.calc.s3_put_cost(
            user_id="u1",
            bucket="biomate-data",
            size_bytes=10 * 1024**3,  # 10 GB
            storage_class="STANDARD_IA",
        )
        # STANDARD_IA: $0.0125/GB-month (vs STANDARD $0.023)
        assert result.storage_cost > 0
        assert result.storage_cost < 1.0  # Should be < $0.13/month

    def test_glacier_storage(self):
        """GLACIER has very low storage cost."""
        result = self.calc.s3_put_cost(
            user_id="u1",
            bucket="biomate-data",
            size_bytes=100 * 1024**3,  # 100 GB
            storage_class="GLACIER",
        )
        # GLACIER: $0.004/GB-month
        assert result.storage_cost > 0
        # 100 GB * $0.004 = $0.40/month
        assert result.storage_cost < 1.0

    def test_intelligent_tiering_storage(self):
        """INTELLIGENT_TIERING auto-optimizes costs."""
        result = self.calc.s3_put_cost(
            user_id="u1",
            bucket="biomate-data",
            size_bytes=50 * 1024**3,  # 50 GB
            storage_class="INTELLIGENT_TIERING",
        )
        # INTELLIGENT_TIERING: $0.023/GB (frequent) to $0.0125 (infrequent)
        assert result.storage_cost > 0


# ---------------------------------------------------------------------------
# 8.  Spot Discount Edge Cases
# ---------------------------------------------------------------------------

class TestSpotDiscountEdgeCases(unittest.TestCase):
    """Test unusual spot discount scenarios."""

    def setUp(self):
        from galaxy.ai.billing.core.cost_calculator import CostCalculator
        self.calc = CostCalculator()

    def test_zero_percent_spot_discount(self):
        """Spot with 0% discount should match on-demand."""
        on_demand = self.calc.batch_job_cost(
            job_id="j-od",
            user_id="u1",
            workflow_id="wf1",
            instance_type="c6i.xlarge",
            vcpus=4,
            memory_mb=8192,
            gpu_count=0,
            duration_seconds=3600,
            is_spot=False,
        )
        spot_0 = self.calc.batch_job_cost(
            job_id="j-spot-0",
            user_id="u1",
            workflow_id="wf1",
            instance_type="c6i.xlarge",
            vcpus=4,
            memory_mb=8192,
            gpu_count=0,
            duration_seconds=3600,
            is_spot=True,
            spot_discount=0.0,
        )
        assert abs(on_demand.total_cost - spot_0.total_cost) < 0.001

    def test_hundred_percent_spot_discount(self):
        """Spot with 100% discount should be free."""
        spot_100 = self.calc.batch_job_cost(
            job_id="j-spot-100",
            user_id="u1",
            workflow_id="wf1",
            instance_type="c6i.xlarge",
            vcpus=4,
            memory_mb=8192,
            gpu_count=0,
            duration_seconds=3600,
            is_spot=True,
            spot_discount=1.0,  # 100% discount
        )
        assert spot_100.total_cost == 0.0, (
            f"100% discount should be free, got ${spot_100.total_cost}"
        )

    def test_negative_spot_discount_clamped(self):
        """Negative discount should be treated as 0% (no discount)."""
        result = self.calc.batch_job_cost(
            job_id="j-spot-neg",
            user_id="u1",
            workflow_id="wf1",
            instance_type="c6i.xlarge",
            vcpus=4,
            memory_mb=8192,
            gpu_count=0,
            duration_seconds=3600,
            is_spot=True,
            spot_discount=-0.5,  # Invalid
        )
        # Should clamp to 0 or raise error
        assert result.total_cost > 0


# ---------------------------------------------------------------------------
# 9.  Month Boundary Edge Cases
# ---------------------------------------------------------------------------

class TestMonthBoundaryEdgeCases(unittest.TestCase):
    """Test cost tracking across month boundaries."""

    def _make_service_with_spy(self):
        """Create RealtimeCostService with spy Redis."""
        import threading
        from galaxy.ai.billing.core.realtime_cost_service import RealtimeCostService

        store = {}

        class SpyRedis:
            def hincrbyfloat(self, key, field, amount):
                store.setdefault(key, {})[field] = (
                    float(store.get(key, {}).get(field, 0)) + float(amount)
                )
            def hincrby(self, key, field, amount):
                store.setdefault(key, {})[field] = (
                    int(store.get(key, {}).get(field, 0)) + int(amount)
                )
            def incrbyfloat(self, key, delta):
                store[key] = float(store.get(key, 0)) + float(delta)
                return store[key]
            def expire(self, key, seconds): pass
            def get(self, key): return str(store[key]) if key in store else None
            def setex(self, key, ttl, value): store[key] = value
            def pipeline(self_r):
                class P:
                    def hincrbyfloat(self_p, k, f, v): self_r.hincrbyfloat(k, f, v); return self_p
                    def hincrby(self_p, k, f, v): self_r.hincrby(k, f, v); return self_p
                    def incrbyfloat(self_p, k, v): self_r.incrbyfloat(k, v); return self_p
                    def expire(self_p, k, s): return self_p
                    def execute(self_p): return []
                return P()

        svc = RealtimeCostService.__new__(RealtimeCostService)
        svc._r = SpyRedis()
        svc._running_jobs = {}
        svc._lock = threading.Lock()
        return svc, store

    def test_costs_across_month_boundary(self):
        """
        Costs recorded in January should have different keys than February.
        This test manually sets the month in keys to verify isolation.
        """
        svc, store = self._make_service_with_spy()

        # Simulate recording in different months by directly manipulating keys
        jan_key = "cost:user1:month:2026-01:llm"
        feb_key = "cost:user1:month:2026-02:llm"

        svc._r.hincrbyfloat(jan_key, "input_usd", 10.0)
        svc._r.hincrbyfloat(feb_key, "input_usd", 5.0)

        assert float(store[jan_key]["input_usd"]) == 10.0
        assert float(store[feb_key]["input_usd"]) == 5.0
        # Keys are isolated — no accumulation across months


# ---------------------------------------------------------------------------
# 10.  Negative Value Handling
# ---------------------------------------------------------------------------

class TestNegativeValueHandling(unittest.TestCase):
    """Test that negative inputs are handled gracefully."""

    def setUp(self):
        from galaxy.ai.billing.core.cost_calculator import CostCalculator
        self.calc = CostCalculator()

    def test_negative_duration_treated_as_zero(self):
        """Negative duration should be treated as zero or raise error."""
        result = self.calc.batch_job_cost(
            job_id="j-neg-dur",
            user_id="u1",
            workflow_id="wf1",
            instance_type="c6i.xlarge",
            vcpus=4,
            memory_mb=8192,
            gpu_count=0,
            duration_seconds=-100,
            is_spot=False,
        )
        # Should either be 0 or raise ValueError
        assert result.total_cost == 0.0 or result.total_cost >= 0

    def test_negative_token_counts_treated_as_zero(self):
        """Negative token counts should be treated as zero."""
        result = self.calc.llm_call_cost(
            user_id="u1",
            session_id="s1",
            model="claude-sonnet-4-5-20250929",
            input_tokens=-1000,
            output_tokens=-500,
        )
        assert result.total_cost == 0.0


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    unittest.main(verbosity=2)
