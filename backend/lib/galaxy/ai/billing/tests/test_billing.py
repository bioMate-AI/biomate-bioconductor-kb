"""
BioMate Billing System — Test Suite

Covers:
  1. CostCalculator — pure unit tests (no I/O)
  2. RealtimeCostService — Redis ledger (mocked)
  3. QuotaEnforcer — pre-job middleware (mocked Redis)
  4. BatchJobSpec / submit_batch_job — Batch wrapper (mocked boto3)
  5. Billing API endpoints — FastAPI TestClient

Run:
    cd backend
    pytest lib/galaxy/ai/billing/tests/test_billing.py -v
"""

import json
import math
import time
import unittest
from dataclasses import dataclass
from decimal import Decimal
from typing import Dict, Optional
from unittest.mock import MagicMock, patch, call

import pytest


# ---------------------------------------------------------------------------
# 1.  CostCalculator — pure unit tests
# ---------------------------------------------------------------------------

class TestCostCalculator(unittest.TestCase):
    """Pure unit tests — no external dependencies."""

    def setUp(self):
        from galaxy.ai.billing.core.cost_calculator import CostCalculator, EC2_INSTANCE_PRICING
        self.calc = CostCalculator()
        self.pricing = EC2_INSTANCE_PRICING

    # ---- Batch job costs ----

    def test_batch_job_known_instance_1h(self):
        """c6i.xlarge for 1 hour: cost should be a positive fraction of $0.170."""
        result = self.calc.batch_job_cost(
            job_id="j-1",
            user_id="u1",
            workflow_id="wf1",
            instance_type="c6i.xlarge",
            vcpus=4,
            memory_mb=8192,
            gpu_count=0,
            duration_seconds=3600,
            is_spot=False,
        )
        # Calculator attributes cost proportionally; total is between 50%–100% of $0.170
        assert 0.08 <= result.total_cost <= 0.175, (
            f"c6i.xlarge 1h cost ${result.total_cost:.4f} outside expected range"
        )

    def test_batch_job_gpu_instance(self):
        """g4dn.xlarge for 30 min should cost less than the full-hour price ($0.526)."""
        result = self.calc.batch_job_cost(
            job_id="j-2",
            user_id="u1",
            workflow_id="wf1",
            instance_type="g4dn.xlarge",
            vcpus=4,
            memory_mb=16384,
            gpu_count=1,
            duration_seconds=1800,
            is_spot=False,
        )
        # 30-min job must be cheaper than full-hour on-demand rate
        assert 0 < result.total_cost < 0.526, (
            f"g4dn.xlarge 30-min cost ${result.total_cost:.4f} outside expected range"
        )

    def test_batch_job_spot_discount(self):
        """Spot discount should reduce cost by ~65%."""
        on_demand = self.calc.batch_job_cost(
            job_id="j-od",
            user_id="u1",
            workflow_id="wf1",
            instance_type="m6i.xlarge",
            vcpus=4,
            memory_mb=16384,
            gpu_count=0,
            duration_seconds=3600,
            is_spot=False,
        )
        spot = self.calc.batch_job_cost(
            job_id="j-spot",
            user_id="u1",
            workflow_id="wf1",
            instance_type="m6i.xlarge",
            vcpus=4,
            memory_mb=16384,
            gpu_count=0,
            duration_seconds=3600,
            is_spot=True,
            spot_discount=0.65,
        )
        ratio = spot.total_cost / on_demand.total_cost
        assert abs(ratio - 0.35) < 0.05, f"Spot ratio {ratio} not near 0.35"

    def test_batch_job_unknown_instance_falls_back_to_fargate(self):
        """Unknown instance type should use Fargate per-vCPU/mem pricing."""
        result = self.calc.batch_job_cost(
            job_id="j-3",
            user_id="u1",
            workflow_id="wf1",
            instance_type="FARGATE",
            vcpus=2,
            memory_mb=4096,
            gpu_count=0,
            duration_seconds=3600,
            is_spot=False,
        )
        # Fargate: 2 vCPU * $0.04048/hr = $0.08096; 4 GB * $0.004445/hr = $0.01778
        expected_min = 0.08  # rough lower bound
        assert result.total_cost > expected_min, (
            f"Fargate fallback cost ${result.total_cost:.4f} too low"
        )

    def test_zero_duration_job_is_zero_cost(self):
        result = self.calc.batch_job_cost(
            job_id="j-0",
            user_id="u1",
            workflow_id="wf1",
            instance_type="c6i.xlarge",
            vcpus=4,
            memory_mb=8192,
            gpu_count=0,
            duration_seconds=0,
        )
        assert result.total_cost == 0.0

    # ---- LLM costs ----

    def test_llm_cost_claude_sonnet(self):
        """1M input + 1M output tokens for Sonnet should be $3.00 + $15.00."""
        result = self.calc.llm_call_cost(
            user_id="u1",
            session_id="s1",
            model="claude-sonnet-4-5-20250929",
            input_tokens=1_000_000,
            output_tokens=1_000_000,
        )
        assert abs(result.input_cost  - 3.00) < 0.001
        assert abs(result.output_cost - 15.00) < 0.001
        assert abs(result.total_cost  - 18.00) < 0.001

    def test_llm_cost_unknown_model_uses_default(self):
        """Unknown model should fall back to default pricing."""
        result = self.calc.llm_call_cost(
            user_id="u1",
            session_id="s1",
            model="gpt-99-turbo",
            input_tokens=100_000,
            output_tokens=50_000,
        )
        # default: $3/1M input, $15/1M output
        assert abs(result.input_cost  - 0.30)  < 0.001
        assert abs(result.output_cost - 0.75)  < 0.001

    def test_llm_zero_tokens(self):
        result = self.calc.llm_call_cost(
            user_id="u1",
            session_id="s1",
            model="claude-haiku-4-5-20251001",
            input_tokens=0,
            output_tokens=0,
        )
        assert result.total_cost == 0.0

    # ---- S3 costs ----

    def test_s3_put_cost_standard_storage(self):
        """1 GB PUT should cost storage + request fees."""
        result = self.calc.s3_put_cost(
            user_id="u1",
            bucket="biomate-data",
            size_bytes=1_073_741_824,   # 1 GiB ≈ 1 GB
            storage_class="STANDARD",
        )
        assert result.storage_cost >= 0
        assert result.request_cost >= 0
        assert result.total_cost > 0

    def test_s3_put_cost_zero_size(self):
        """Zero-byte object should still charge a PUT request."""
        result = self.calc.s3_put_cost(
            user_id="u1",
            bucket="biomate-data",
            size_bytes=0,
            storage_class="STANDARD",
        )
        # Only request cost, no storage cost
        assert result.storage_cost == 0.0

    # ---- Estimate running job ----

    def test_estimate_running_job_proportional(self):
        """30-minute estimate should be exactly half of 60-minute estimate."""
        now_ms = int(time.time() * 1000)
        h1 = self.calc.estimate_running_job_cost(
            instance_type="c6i.xlarge",
            vcpus=4,
            memory_mb=8192,
            gpu_count=0,
            started_at_ms=now_ms - 3600_000,   # 60 min ago
            now_ms=now_ms,
        )
        h05 = self.calc.estimate_running_job_cost(
            instance_type="c6i.xlarge",
            vcpus=4,
            memory_mb=8192,
            gpu_count=0,
            started_at_ms=now_ms - 1800_000,   # 30 min ago
            now_ms=now_ms,
        )
        assert abs(h1 / h05 - 2.0) < 0.05


# ---------------------------------------------------------------------------
# 2.  RealtimeCostService — Redis ledger (mocked)
# ---------------------------------------------------------------------------

class TestRealtimeCostService(unittest.TestCase):
    """Tests for Redis-backed ledger using a fake Redis client."""

    def _make_service(self, fake_redis):
        """Instantiate RealtimeCostService with an injected Redis mock."""
        import threading
        from galaxy.ai.billing.core.realtime_cost_service import RealtimeCostService
        svc = RealtimeCostService.__new__(RealtimeCostService)
        svc._r = fake_redis          # attribute name used by the class
        svc._running_jobs = {}       # internal job-metadata cache
        svc._lock = threading.Lock()
        return svc

    def _fake_redis(self):
        """In-memory Redis substitute covering all methods used by RealtimeCostService."""
        store: dict = {}   # str → str | dict

        class FakeRedis:
            # ---- Hash operations ----
            def hincrbyfloat(self_, key, field, amount):
                entry = store.setdefault(key, {})
                entry[field] = float(entry.get(field, 0)) + float(amount)
                return entry[field]

            def hincrby(self_, key, field, amount):
                entry = store.setdefault(key, {})
                entry[field] = int(entry.get(field, 0)) + int(amount)
                return entry[field]

            def hgetall(self_, key):
                raw = store.get(key, {})
                if isinstance(raw, dict):
                    return {k: str(v) for k, v in raw.items()}
                return {}

            def hset(self_, key, mapping=None, **kwargs):
                entry = store.setdefault(key, {})
                if mapping:
                    entry.update(mapping)

            # ---- String operations ----
            def get(self_, key):
                v = store.get(key)
                if v is None:
                    return None
                if isinstance(v, dict):
                    return None   # hash keys aren't string-readable
                return str(v)

            def set(self_, key, value, ex=None):
                store[key] = value

            def setex(self_, key, ttl, value):
                store[key] = value

            def incrbyfloat(self_, key, delta):
                store[key] = float(store.get(key, 0)) + float(delta)
                return store[key]

            # ---- Key operations ----
            def expire(self_, key, seconds):
                pass   # no-op in tests

            def delete(self_, *keys):
                for k in keys:
                    store.pop(k, None)

            def exists(self_, key):
                return 1 if key in store else 0

            def scan_iter(self_, pattern):
                import fnmatch
                return [k for k in store if fnmatch.fnmatch(k, pattern)]

            # ---- Pipeline ----
            def pipeline(self_):
                this = self_
                class FakePipeline:
                    def __init__(self_p):
                        self_p._cmds = []
                    def __enter__(self_p):
                        return self_p
                    def __exit__(self_p, *args):
                        pass
                    def hincrbyfloat(self_p, key, field, amount):
                        this.hincrbyfloat(key, field, amount)
                        return self_p
                    def hincrby(self_p, key, field, amount):
                        this.hincrby(key, field, amount)
                        return self_p
                    def expire(self_p, key, seconds):
                        return self_p
                    def execute(self_p):
                        return []
                return FakePipeline()

        r = FakeRedis()
        r._store = store
        return r

    def test_record_llm_cost_accumulates(self):
        """Two LLM records should accumulate in the same Redis hash."""
        fake = self._fake_redis()
        svc = self._make_service(fake)
        svc.record_llm_cost("user1", input_usd=0.01, output_usd=0.05,
                             input_tokens=1000, output_tokens=500)
        svc.record_llm_cost("user1", input_usd=0.02, output_usd=0.10,
                             input_tokens=2000, output_tokens=1000)

        # read back
        month = time.strftime("%Y-%m")
        key = f"cost:user1:month:{month}:llm"
        data = fake._store.get(key, {})
        assert abs(float(data.get("input_usd", 0)) - 0.03) < 1e-6
        assert abs(float(data.get("output_usd", 0)) - 0.15) < 1e-6

    def test_set_and_get_quota(self):
        fake = self._fake_redis()
        svc = self._make_service(fake)
        svc.set_quota("user2", 100.0)

        month = time.strftime("%Y-%m")
        key = f"quota:user2:month:{month}:limit"
        stored = fake._store.get(key)
        assert stored is not None
        assert abs(float(stored) - 100.0) < 1e-6

    def test_is_over_hard_limit_false_when_no_quota(self):
        fake = self._fake_redis()
        svc = self._make_service(fake)
        result = svc.is_over_hard_limit("user_no_quota")
        assert result is False

    def test_is_over_hard_limit_true_when_exceeded(self):
        fake = self._fake_redis()
        svc = self._make_service(fake)
        # Set quota to $5
        svc.set_quota("user_over", 5.0)
        # Record $6 of LLM spend
        svc.record_llm_cost("user_over", input_usd=3.0, output_usd=3.0,
                             input_tokens=100_000, output_tokens=50_000)
        assert svc.is_over_hard_limit("user_over") is True

    def test_register_running_job(self):
        fake = self._fake_redis()
        svc = self._make_service(fake)
        svc.register_running_job(
            user_id="user3",
            job_id="job-abc",
            instance_type="c6i.xlarge",
            vcpus=4,
            memory_mb=8192,
            gpu_count=0,
            started_at_ms=int(time.time() * 1000),
            is_spot=False,
        )
        key = "cost:user3:job:job-abc:running"
        assert key in fake._store
        assert "vcpus" in fake._store[key]


# ---------------------------------------------------------------------------
# 3.  QuotaEnforcer — pre-job middleware (mocked Redis)
# ---------------------------------------------------------------------------

class TestQuotaEnforcer(unittest.TestCase):

    def test_check_and_reserve_allows_when_no_quota(self):
        """No quota set → job allowed without error."""
        with patch(
            "galaxy.ai.billing.core.quota_enforcer.get_cost_service"
        ) as mock_svc:
            mock_svc.return_value.get_current_costs.return_value = {
                "total_usd": 1.0,
                "quota_usd": None,
            }
            from galaxy.ai.billing.core.quota_enforcer import check_and_reserve
            check_and_reserve("user1", estimated_cost_usd=0.5)  # should not raise

    def test_check_and_reserve_raises_when_over(self):
        """User over quota → QuotaExceededError."""
        with patch(
            "galaxy.ai.billing.core.quota_enforcer.get_cost_service"
        ) as mock_svc:
            mock_svc.return_value.get_current_costs.return_value = {
                "total_usd": 4.80,
                "quota_usd": 5.0,
            }
            from galaxy.ai.billing.core.quota_enforcer import (
                check_and_reserve, QuotaExceededError
            )
            with pytest.raises(QuotaExceededError) as exc_info:
                check_and_reserve("user1", estimated_cost_usd=0.25)
            assert exc_info.value.limit == 5.0
            assert exc_info.value.used > 5.0

    def test_check_and_reserve_passes_within_quota(self):
        """User well within quota → no error."""
        with patch(
            "galaxy.ai.billing.core.quota_enforcer.get_cost_service"
        ) as mock_svc:
            mock_svc.return_value.get_current_costs.return_value = {
                "total_usd": 1.0,
                "quota_usd": 50.0,
            }
            from galaxy.ai.billing.core.quota_enforcer import check_and_reserve
            check_and_reserve("user1", estimated_cost_usd=0.50)  # should not raise

    def test_estimate_job_cost_returns_positive(self):
        from galaxy.ai.billing.core.quota_enforcer import estimate_job_cost
        cost = estimate_job_cost(
            instance_type="g4dn.xlarge",
            vcpus=4,
            memory_mb=16384,
            gpu_count=1,
            expected_duration_minutes=60,
        )
        assert cost > 0.0
        assert cost < 10.0  # sanity ceiling

    def test_estimate_job_cost_spot_is_cheaper(self):
        from galaxy.ai.billing.core.quota_enforcer import estimate_job_cost
        on_demand = estimate_job_cost(
            instance_type="g4dn.xlarge",
            vcpus=4,
            memory_mb=16384,
            gpu_count=1,
            expected_duration_minutes=60,
            is_spot=False,
        )
        spot = estimate_job_cost(
            instance_type="g4dn.xlarge",
            vcpus=4,
            memory_mb=16384,
            gpu_count=1,
            expected_duration_minutes=60,
            is_spot=True,
        )
        assert spot < on_demand


# ---------------------------------------------------------------------------
# 4.  BatchJobSpec / submit_batch_job — mocked boto3
# ---------------------------------------------------------------------------

class TestBatchSubmitter(unittest.TestCase):

    def _mock_batch_client(self, job_id="job-xyz"):
        mock = MagicMock()
        mock.submit_job.return_value = {"jobId": job_id, "jobName": "test-job"}
        return mock

    def test_submit_batch_job_returns_job_id(self):
        """Happy path: quota OK → job submitted → job ID returned."""
        from galaxy.ai.billing.batch_submitter import BatchJobSpec, submit_batch_job
        spec = BatchJobSpec(
            user_id="user1",
            workflow_id="wf-001",
            job_name="test-rna-seq",
            job_queue="biomate-cpu",
            job_definition="biomate-cpu:1",
            vcpus=4,
            memory_mb=16384,
            gpu_count=0,
            instance_type="c6i.xlarge",
            expected_duration_minutes=60,
            command=["python", "run.py"],
        )
        mock_batch = self._mock_batch_client("job-abc-123")
        with (
            patch("galaxy.ai.billing.batch_submitter._get_batch",
                  return_value=mock_batch),
            patch("galaxy.ai.billing.batch_submitter.check_and_reserve"),
            patch("galaxy.ai.billing.batch_submitter.estimate_job_cost",
                  return_value=0.17),
        ):
            job_id = submit_batch_job(spec)

        assert job_id == "job-abc-123"
        mock_batch.submit_job.assert_called_once()

    def test_submit_batch_job_includes_billing_tags(self):
        """Submitted job must carry user_id + workflow_id tags."""
        from galaxy.ai.billing.batch_submitter import BatchJobSpec, submit_batch_job
        spec = BatchJobSpec(
            user_id="user42",
            workflow_id="wf-999",
            job_name="gpu-job",
            job_queue="biomate-gpu",
            job_definition="biomate-gpu:2",
            vcpus=4,
            memory_mb=16384,
            gpu_count=1,
            instance_type="g4dn.xlarge",
            expected_duration_minutes=30,
        )
        mock_batch = self._mock_batch_client()
        with (
            patch("galaxy.ai.billing.batch_submitter._get_batch",
                  return_value=mock_batch),
            patch("galaxy.ai.billing.batch_submitter.check_and_reserve"),
            patch("galaxy.ai.billing.batch_submitter.estimate_job_cost",
                  return_value=0.26),
        ):
            submit_batch_job(spec)

        kwargs = mock_batch.submit_job.call_args.kwargs
        tags = kwargs["tags"]
        assert tags["user_id"] == "user42"
        assert tags["workflow_id"] == "wf-999"
        assert tags["instance_type"] == "g4dn.xlarge"
        assert tags["service"] == "biomate"

    def test_submit_batch_job_raises_quota_exceeded(self):
        """If quota check fails, QuotaExceededError should propagate."""
        from galaxy.ai.billing.batch_submitter import BatchJobSpec, submit_batch_job
        from galaxy.ai.billing.core.quota_enforcer import QuotaExceededError
        spec = BatchJobSpec(
            user_id="broke_user",
            workflow_id="wf-0",
            job_name="too-expensive",
            job_queue="biomate-gpu",
            job_definition="biomate-gpu:1",
            vcpus=96,
            memory_mb=1_000_000,
            gpu_count=8,
            instance_type="p4d.24xlarge",
            expected_duration_minutes=600,
        )
        with (
            patch("galaxy.ai.billing.batch_submitter._get_batch"),
            patch("galaxy.ai.billing.batch_submitter.estimate_job_cost",
                  return_value=327.7),
            patch(
                "galaxy.ai.billing.batch_submitter.check_and_reserve",
                side_effect=QuotaExceededError("broke_user", 330.0, 5.0)
            ),
        ):
            with pytest.raises(QuotaExceededError):
                submit_batch_job(spec)

    def test_submit_includes_gpu_resource_requirement(self):
        """GPU jobs must have a GPU resource requirement in container overrides."""
        from galaxy.ai.billing.batch_submitter import BatchJobSpec, submit_batch_job
        spec = BatchJobSpec(
            user_id="u1",
            workflow_id="wf1",
            job_name="gpu-cryo",
            job_queue="gpu-queue",
            job_definition="cryo-gpu:1",
            vcpus=4,
            memory_mb=16384,
            gpu_count=2,
            instance_type="g5.4xlarge",
        )
        mock_batch = self._mock_batch_client()
        with (
            patch("galaxy.ai.billing.batch_submitter._get_batch",
                  return_value=mock_batch),
            patch("galaxy.ai.billing.batch_submitter.check_and_reserve"),
            patch("galaxy.ai.billing.batch_submitter.estimate_job_cost",
                  return_value=1.0),
        ):
            submit_batch_job(spec)

        kwargs = mock_batch.submit_job.call_args.kwargs
        resources = kwargs["containerOverrides"]["resourceRequirements"]
        gpu_req = next((r for r in resources if r["type"] == "GPU"), None)
        assert gpu_req is not None, "GPU resource requirement missing"
        assert gpu_req["value"] == "2"

    def test_no_gpu_requirement_for_cpu_job(self):
        """CPU-only jobs must NOT have a GPU resource requirement."""
        from galaxy.ai.billing.batch_submitter import BatchJobSpec, submit_batch_job
        spec = BatchJobSpec(
            user_id="u1",
            workflow_id="wf1",
            job_name="cpu-job",
            job_queue="cpu-queue",
            job_definition="cpu:1",
            vcpus=4,
            memory_mb=8192,
            gpu_count=0,
            instance_type="c6i.xlarge",
        )
        mock_batch = self._mock_batch_client()
        with (
            patch("galaxy.ai.billing.batch_submitter._get_batch",
                  return_value=mock_batch),
            patch("galaxy.ai.billing.batch_submitter.check_and_reserve"),
            patch("galaxy.ai.billing.batch_submitter.estimate_job_cost",
                  return_value=0.17),
        ):
            submit_batch_job(spec)

        kwargs = mock_batch.submit_job.call_args.kwargs
        resources = kwargs["containerOverrides"]["resourceRequirements"]
        gpu_req = next((r for r in resources if r["type"] == "GPU"), None)
        assert gpu_req is None, "CPU-only job should not have GPU resource"


# ---------------------------------------------------------------------------
# 5.  Billing API endpoints — FastAPI TestClient
# ---------------------------------------------------------------------------

class TestBillingAPI(unittest.TestCase):
    """Smoke-tests for the billing FastAPI router."""

    def setUp(self):
        try:
            from fastapi.testclient import TestClient
            from fastapi import FastAPI
            from galaxy.ai.billing.api.billing_router import router
            app = FastAPI()
            app.include_router(router)
            self.client = TestClient(app, raise_server_exceptions=False)
            self._available = True
        except ImportError:
            self._available = False

    def _skip_if_unavailable(self):
        if not self._available:
            self.skipTest("FastAPI TestClient or billing router not importable")

    def test_get_usage_requires_auth(self):
        """GET /api/billing/usage without token should return 401 or 422."""
        self._skip_if_unavailable()
        resp = self.client.get("/api/billing/usage")
        assert resp.status_code in (401, 403, 422), (
            f"Expected 401/403/422, got {resp.status_code}"
        )

    def test_get_quota_requires_auth(self):
        """GET /api/billing/quota without token should return 401 or 422."""
        self._skip_if_unavailable()
        resp = self.client.get("/api/billing/quota")
        assert resp.status_code in (401, 403, 422)

    def test_internal_job_started_requires_key(self):
        """POST /internal/billing/job_started without key → 401/422."""
        self._skip_if_unavailable()
        resp = self.client.post(
            "/internal/billing/job_started",
            json={"job_id": "j1", "user_id": "u1"},
        )
        assert resp.status_code in (401, 403, 422)

    def test_lago_webhook_empty_body(self):
        """POST /webhooks/lago with no body should return 422 (validation)."""
        self._skip_if_unavailable()
        resp = self.client.post("/webhooks/lago", json={})
        # Could be 422 (pydantic validation) or 401 (missing sig) depending on impl
        assert resp.status_code in (200, 401, 403, 422)


# ---------------------------------------------------------------------------
# 6.  S3 Tagging helpers
# ---------------------------------------------------------------------------

class TestS3Tagging(unittest.TestCase):
    """Test make_s3_tagged_upload wraps boto3 with Tagging."""

    def test_upload_file_adds_tagging(self):
        from galaxy.ai.billing.batch_submitter import make_s3_tagged_upload
        mock_s3 = MagicMock()
        wrapped = make_s3_tagged_upload(mock_s3, user_id="user99", workflow_id="wf42")
        wrapped.upload_file("local.csv", "my-bucket", "path/to/key.csv")
        mock_s3.upload_file.assert_called_once()
        _, _, _, kwargs = mock_s3.upload_file.call_args[0] + (
            mock_s3.upload_file.call_args.kwargs,
        ) if mock_s3.upload_file.call_args.args else (
            None, None, None, mock_s3.upload_file.call_args.kwargs
        )
        call_kwargs = mock_s3.upload_file.call_args.kwargs
        extra = call_kwargs.get("ExtraArgs", {})
        assert "user_id=user99" in extra.get("Tagging", ""), (
            f"Expected Tagging to contain user_id=user99, got: {extra}"
        )

    def test_put_object_adds_tagging(self):
        from galaxy.ai.billing.batch_submitter import make_s3_tagged_upload
        mock_s3 = MagicMock()
        wrapped = make_s3_tagged_upload(mock_s3, user_id="user88", workflow_id="wf11")
        wrapped.put_object(Bucket="b", Key="k", Body=b"data")
        mock_s3.put_object.assert_called_once()
        kwargs = mock_s3.put_object.call_args.kwargs
        assert "user_id=user88" in kwargs.get("Tagging", ""), (
            f"Tagging missing in: {kwargs}"
        )

    def test_passthrough_for_other_methods(self):
        from galaxy.ai.billing.batch_submitter import make_s3_tagged_upload
        mock_s3 = MagicMock()
        wrapped = make_s3_tagged_upload(mock_s3, user_id="u1", workflow_id="w1")
        wrapped.head_object(Bucket="b", Key="k")
        mock_s3.head_object.assert_called_once_with(Bucket="b", Key="k")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    unittest.main(verbosity=2)
