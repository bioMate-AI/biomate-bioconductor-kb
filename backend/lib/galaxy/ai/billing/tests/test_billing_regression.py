"""
BioMate Billing — Regression Test Suite

Each test is named after the exact bug it would have caught.
All were discovered during a professional audit; none were caught
by the original test suite because the original tests only exercise
happy paths with mocked dependencies.
"""

import importlib
import json
import time
import threading
import unittest
from unittest.mock import MagicMock, AsyncMock, patch, call
import pytest


def _import_lambda(module_name: str):
    """Import a module from the 'lambda' package (reserved keyword workaround)."""
    return importlib.import_module(f"galaxy.ai.billing.lambda.{module_name}")


# ---------------------------------------------------------------------------
# 1.  CostCalculator — cost attribution correctness
# ---------------------------------------------------------------------------

class TestCostAttributionRegressions(unittest.TestCase):
    """
    BUG: CPU-only jobs were attributed at 50% vCPU + 30% memory = 80% of instance cost.
    BUG: GPU jobs were also 80% (50% + 30%) before the GPU share was added.
    After fix: CPU-only = 60+40 = 100%, GPU = 50+30+20 = 100%.
    """

    def setUp(self):
        from galaxy.ai.billing.core.cost_calculator import CostCalculator, EC2_INSTANCE_PRICING
        self.calc = CostCalculator()
        self.pricing = EC2_INSTANCE_PRICING

    def test_cpu_only_job_attributes_100_percent_of_instance_cost(self):
        """
        c6i.xlarge full instance for 1 hour costs $0.170.
        A job requesting all 4 vCPU and 8 GB (= full instance) must be billed
        exactly $0.170, not $0.136 (the old 80% bug).
        """
        result = self.calc.batch_job_cost(
            job_id="j-full",
            user_id="u1",
            workflow_id="wf1",
            instance_type="c6i.xlarge",
            vcpus=4,           # full instance
            memory_mb=8192,    # full instance
            gpu_count=0,
            duration_seconds=3600,
            is_spot=False,
        )
        instance_price = self.pricing["c6i.xlarge"]["price_hr"]  # $0.170
        # Must attribute 100% — tolerate floating-point rounding only
        assert abs(result.total_cost - instance_price) < 0.0001, (
            f"CPU-only full-instance: expected ${instance_price:.4f}, "
            f"got ${result.total_cost:.4f}. "
            f"Breakdown: vcpu=${result.vcpu_cost:.4f} mem=${result.memory_cost:.4f}"
        )

    def test_gpu_job_attributes_100_percent_of_instance_cost(self):
        """
        g4dn.xlarge full instance for 1 hour costs $0.526.
        GPU job using all resources must total exactly $0.526.
        """
        result = self.calc.batch_job_cost(
            job_id="j-gpu",
            user_id="u1",
            workflow_id="wf1",
            instance_type="g4dn.xlarge",
            vcpus=4,
            memory_mb=16384,
            gpu_count=1,
            duration_seconds=3600,
            is_spot=False,
        )
        instance_price = self.pricing["g4dn.xlarge"]["price_hr"]  # $0.526
        assert abs(result.total_cost - instance_price) < 0.0001, (
            f"GPU full-instance: expected ${instance_price:.4f}, "
            f"got ${result.total_cost:.4f}. "
            f"Breakdown: vcpu=${result.vcpu_cost:.4f} mem=${result.memory_cost:.4f} gpu=${result.gpu_cost:.4f}"
        )

    def test_cpu_cost_split_sums_to_100_percent(self):
        """CPU-only: vcpu_cost + memory_cost must equal total_cost exactly."""
        result = self.calc.batch_job_cost(
            job_id="j-cpu",
            user_id="u1",
            workflow_id="wf1",
            instance_type="m6i.2xlarge",
            vcpus=8,
            memory_mb=32768,
            gpu_count=0,
            duration_seconds=7200,
            is_spot=False,
        )
        assert result.gpu_cost == 0.0
        assert abs(result.vcpu_cost + result.memory_cost - result.total_cost) < 1e-8, (
            f"CPU-only components don't sum to total: "
            f"vcpu={result.vcpu_cost} + mem={result.memory_cost} = "
            f"{result.vcpu_cost + result.memory_cost} != {result.total_cost}"
        )

    def test_gpu_cost_split_sums_to_100_percent(self):
        """GPU: vcpu_cost + memory_cost + gpu_cost must equal total_cost."""
        result = self.calc.batch_job_cost(
            job_id="j-gpu-sum",
            user_id="u1",
            workflow_id="wf1",
            instance_type="g5.2xlarge",
            vcpus=8,
            memory_mb=32768,
            gpu_count=1,
            duration_seconds=3600,
            is_spot=False,
        )
        component_sum = result.vcpu_cost + result.memory_cost + result.gpu_cost
        assert abs(component_sum - result.total_cost) < 1e-8, (
            f"GPU components don't sum to total: {component_sum} != {result.total_cost}"
        )


# ---------------------------------------------------------------------------
# 2.  RealtimeCostService — integer token accumulation
# ---------------------------------------------------------------------------

class TestRealtimeCostServiceRegressions(unittest.TestCase):
    """
    BUG: Token counts used hincrbyfloat, causing floating-point drift.
    Fix: Token counts use hincrby (integer).
    """

    def _make_service_with_spy(self):
        """Return (service, call_log) where call_log records all Redis calls."""
        import threading
        from galaxy.ai.billing.core.realtime_cost_service import RealtimeCostService

        call_log = []

        class SpyRedis:
            """Records every Redis call; delegates to in-memory store for correctness."""
            def __init__(self):
                self._store = {}

            def hincrbyfloat(self, key, field, amount):
                call_log.append(("hincrbyfloat", key, field))
                self._store.setdefault(key, {})[field] = (
                    float(self._store.get(key, {}).get(field, 0)) + float(amount)
                )

            def hincrby(self, key, field, amount):
                call_log.append(("hincrby", key, field))
                self._store.setdefault(key, {})[field] = (
                    int(self._store.get(key, {}).get(field, 0)) + int(amount)
                )

            def incrbyfloat(self, key, delta):
                self._store[key] = float(self._store.get(key, 0)) + float(delta)
                return self._store[key]

            def expire(self, key, seconds): pass
            def delete(self, *keys):
                for k in keys: self._store.pop(k, None)
            def exists(self, key): return 1 if key in self._store else 0
            def get(self, key): return str(self._store[key]) if key in self._store else None
            def setex(self, key, ttl, value): self._store[key] = value
            def scan_iter(self, pattern): return []

            def pipeline(self_r):
                spy = self_r
                class P:
                    def hincrbyfloat(self_p, k, f, v): spy.hincrbyfloat(k, f, v); return self_p
                    def hincrby(self_p, k, f, v): spy.hincrby(k, f, v); return self_p
                    def incrbyfloat(self_p, k, v): spy.incrbyfloat(k, v); return self_p
                    def expire(self_p, k, s): return self_p
                    def delete(self_p, *keys): spy.delete(*keys); return self_p
                    def execute(self_p): return []
                return P()

        svc = RealtimeCostService.__new__(RealtimeCostService)
        svc._r = SpyRedis()
        svc._running_jobs = {}
        svc._lock = threading.Lock()
        return svc, call_log

    def test_token_counts_use_hincrby_not_hincrbyfloat(self):
        """
        input_tokens and output_tokens must accumulate via hincrby (integer),
        not hincrbyfloat. Over billions of calls, hincrbyfloat accrues fp drift.
        """
        svc, call_log = self._make_service_with_spy()
        svc.record_llm_cost(
            user_id="u1",
            input_usd=0.01,
            output_usd=0.05,
            input_tokens=1000,
            output_tokens=500,
        )

        token_ops = [(op, field) for op, _key, field in call_log
                     if field in ("input_tokens", "output_tokens")]

        # Must use hincrby for integer fields
        for op, field in token_ops:
            assert op == "hincrby", (
                f"Token field '{field}' used '{op}' — must use 'hincrby' to avoid fp drift"
            )

    def test_batch_job_delete_is_inside_pipeline(self):
        """
        record_batch_job_cost must delete the running-job key inside the pipeline
        so that a Redis failure cannot leave a stale running estimate behind.
        The delete must appear in the pipeline call sequence before execute().
        """
        import threading
        from galaxy.ai.billing.core.realtime_cost_service import RealtimeCostService

        pipeline_ops = []

        class TrackingRedis:
            def __init__(self):
                self._store = {}

            def incrbyfloat(self, key, delta):
                self._store[key] = float(self._store.get(key, 0)) + float(delta)
                return self._store[key]
            def expire(self, key, s): pass
            def get(self, key): return str(self._store[key]) if key in self._store else None
            def exists(self, key): return 0
            def setex(self, key, ttl, value): self._store[key] = value

            def pipeline(self_r):
                class P:
                    def hincrbyfloat(self_p, k, f, v):
                        pipeline_ops.append(("hincrbyfloat", k, f))
                        self_r._store.setdefault(k, {})[f] = float(
                            self_r._store.get(k, {}).get(f, 0)) + float(v)
                        return self_p
                    def hincrby(self_p, k, f, v):
                        pipeline_ops.append(("hincrby", k, f))
                        return self_p
                    def expire(self_p, k, s):
                        pipeline_ops.append(("expire", k, None))
                        return self_p
                    def delete(self_p, *keys):
                        for key in keys:
                            pipeline_ops.append(("delete", key, None))
                        return self_p
                    def execute(self_p):
                        pipeline_ops.append(("execute", None, None))
                        return []
                return P()

        svc = RealtimeCostService.__new__(RealtimeCostService)
        svc._r = TrackingRedis()
        svc._running_jobs = {"job-xyz": {}}
        svc._lock = threading.Lock()

        svc.record_batch_job_cost(
            user_id="u1", job_id="job-xyz",
            vcpu_usd=0.10, gpu_usd=0.00, mem_usd=0.04,
            duration_seconds=600,
        )

        ops = [(op, key) for op, key, _ in pipeline_ops]
        execute_idx = next(i for i, (op, _) in enumerate(ops) if op == "execute")
        delete_indices = [i for i, (op, _) in enumerate(ops) if op == "delete"]

        assert delete_indices, "delete not called at all — running estimate never cleaned up"
        assert all(idx < execute_idx for idx in delete_indices), (
            f"delete (indices {delete_indices}) must come before execute (index {execute_idx})"
        )


# ---------------------------------------------------------------------------
# 3.  billing_router — input validation regressions
# ---------------------------------------------------------------------------

class TestBillingRouterRegressions(unittest.TestCase):

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
            self.skipTest("FastAPI TestClient not available")

    def test_empty_string_user_id_rejected(self):
        """
        BUG: JWT with user_id="" passed the `if user_id is None` check,
        returning "" as a valid user id and polluting Redis cost keys.
        Fix: str(user_id).strip() must be non-empty.
        """
        self._skip_if_unavailable()
        import jwt
        import os
        secret = os.environ.get("JWT_SECRET", "")
        if not secret:
            # Dev mode: token IS the user_id directly — send empty string
            token = ""
        else:
            token = jwt.encode({"user_id": "", "exp": 9999999999}, secret, algorithm="HS256")

        resp = self.client.get(
            "/api/billing/usage",
            headers={"Authorization": f"Bearer {token}"},
        )
        # Must be rejected — 401 (empty uid) or 422 (missing required header)
        assert resp.status_code in (401, 422), (
            f"Expected 401/422 for empty user_id, got {resp.status_code}: {resp.text}"
        )

    def test_history_months_clamped_to_24(self):
        """
        BUG: `months=10000` was accepted, causing 10,000 Redis lookups per request.
        Fix: clamp to max(1, min(months, 24)).
        Without clamping, the endpoint would hang or exhaust Redis connections.
        """
        self._skip_if_unavailable()
        import os
        # In dev mode (no JWT_SECRET) the raw token string IS the user_id
        os.environ.pop("JWT_SECRET", None)

        with patch(
            "galaxy.ai.billing.api.billing_router.get_cost_service"
        ) as mock_svc:
            mock_svc.return_value.get_current_costs.return_value = {
                "total_usd": 0.0, "quota_usd": None, "quota_pct": None,
                "running_jobs": [], "running_estimate_usd": 0.0, "committed_usd": 0.0,
                "breakdown": {
                    "llm": {}, "compute": {}, "storage": {}
                },
                "user_id": "u1", "month": "2026-02", "currency": "USD",
            }
            resp = self.client.get(
                "/api/billing/usage/history",
                params={"months": 10000},
                headers={"Authorization": "Bearer u1"},
            )

        if resp.status_code == 200:
            data = resp.json()
            history = data.get("history", [])
            assert len(history) <= 24, (
                f"months=10000 returned {len(history)} entries — clamp to 24 not applied"
            )

    def test_history_months_minimum_is_1(self):
        """months=0 should be treated as 1, not return an empty list."""
        self._skip_if_unavailable()
        import os
        os.environ.pop("JWT_SECRET", None)

        with patch(
            "galaxy.ai.billing.api.billing_router.get_cost_service"
        ) as mock_svc:
            mock_svc.return_value.get_current_costs.return_value = {
                "total_usd": 0.0, "quota_usd": None, "quota_pct": None,
                "running_jobs": [], "running_estimate_usd": 0.0, "committed_usd": 0.0,
                "breakdown": {"llm": {}, "compute": {}, "storage": {}},
                "user_id": "u1", "month": "2026-02", "currency": "USD",
            }
            resp = self.client.get(
                "/api/billing/usage/history",
                params={"months": 0},
                headers={"Authorization": "Bearer u1"},
            )

        if resp.status_code == 200:
            history = resp.json().get("history", [])
            assert len(history) >= 1, "months=0 returned empty history — minimum should be 1"


# ---------------------------------------------------------------------------
# 4.  batch_event_handler — GPU type matching regression
# ---------------------------------------------------------------------------

class TestBatchEventHandlerRegressions(unittest.TestCase):
    """
    BUG: Only `"GPU"` matched; `"NVIDIA_GPU"`, `"AMD_GPU"`, etc. returned gpu_count=0.
    Fix: check against the full set {"GPU", "NVIDIA_GPU", "AMD_GPU", "TRAINIUM", "HABANA"}.
    """

    def _make_job(self, resource_type: str, value: str = "4") -> dict:
        return {
            "container": {
                "vcpus": 8,
                "memory": 32768,
                "resourceRequirements": [
                    {"type": resource_type, "value": value}
                ],
            },
            "tags": {},
        }

    def _get_instance_info(self, job):
        beh = _import_lambda("batch_event_handler")
        return beh._get_instance_info(job)

    def test_nvidia_gpu_type_detected(self):
        """NVIDIA_GPU resource type must count as GPU compute."""
        _, _, _, gpu_count, _ = self._get_instance_info(self._make_job("NVIDIA_GPU", "1"))
        assert gpu_count == 1, f"NVIDIA_GPU not detected; got gpu_count={gpu_count}"

    def test_amd_gpu_type_detected(self):
        _, _, _, gpu_count, _ = self._get_instance_info(self._make_job("AMD_GPU", "1"))
        assert gpu_count == 1, f"AMD_GPU not detected; got gpu_count={gpu_count}"

    def test_trainium_type_detected(self):
        _, _, _, gpu_count, _ = self._get_instance_info(self._make_job("TRAINIUM", "2"))
        assert gpu_count == 2, f"TRAINIUM not detected; got gpu_count={gpu_count}"

    def test_habana_type_detected(self):
        _, _, _, gpu_count, _ = self._get_instance_info(self._make_job("HABANA", "1"))
        assert gpu_count == 1, f"HABANA not detected; got gpu_count={gpu_count}"

    def test_multiple_gpu_resources_accumulate(self):
        """Multiple GPU resource entries should sum, not overwrite."""
        job = {
            "container": {
                "vcpus": 8, "memory": 32768,
                "resourceRequirements": [
                    {"type": "GPU", "value": "2"},
                    {"type": "NVIDIA_GPU", "value": "2"},
                ],
            },
            "tags": {},
        }
        _, _, _, gpu_count, _ = self._get_instance_info(job)
        assert gpu_count == 4, f"Expected 4 GPUs from two entries, got {gpu_count}"

    def test_vcpu_resource_type_not_counted_as_gpu(self):
        """VCPU resource type must not be counted as GPU."""
        _, _, _, gpu_count, _ = self._get_instance_info(self._make_job("VCPU", "8"))
        assert gpu_count == 0, f"VCPU counted as GPU; got gpu_count={gpu_count}"

    def test_describe_job_api_failure_returns_empty_dict(self):
        """
        BUG: _describe_job had no try/except. AWS Batch API error = uncaught exception
        crashing the Lambda and silently losing the billing event.
        Fix: wrap in try/except; return {} on error.
        """
        batch_event_handler = _import_lambda("batch_event_handler")
        with patch.object(batch_event_handler.batch_client, "describe_jobs",
                          side_effect=Exception("ThrottlingException")):
            result = batch_event_handler._describe_job("job-xyz")
        assert result == {}, f"Expected empty dict on API error, got {result}"


# ---------------------------------------------------------------------------
# 5.  s3_event_handler — size validation regression
# ---------------------------------------------------------------------------

class TestS3EventHandlerRegressions(unittest.TestCase):
    """
    BUG: No size validation — AWS SDK truncation bug or API error could
    return negative or exabyte-scale sizes, billing the user impossibly.
    Fix: reject size_bytes outside [0, 5 TiB].
    """

    def _process_record(self, size_bytes: int) -> None:
        """Helper: build minimal S3 record and call _process_record."""
        s3_event_handler = _import_lambda("s3_event_handler")
        record = {
            "eventName": "ObjectCreated:Put",
            "s3": {
                "bucket": {"name": "biomate-data"},
                "object": {"key": "results/output.csv", "size": size_bytes},
            },
        }
        with (
            patch.object(s3_event_handler, "_get_object_tags",
                         return_value={"user_id": "u1", "workflow_id": "wf1"}),
            patch.object(s3_event_handler, "_notify_billing") as mock_notify,
        ):
            s3_event_handler._process_record(record)
            return mock_notify

    def test_normal_size_object_is_billed(self):
        """100 MB object should pass validation and trigger billing."""
        mock_notify = self._process_record(100 * 1024 * 1024)
        mock_notify.assert_called_once()

    def test_zero_size_triggers_head_object_fallback(self):
        """Zero-size events should call _get_object_size, not skip billing."""
        s3_event_handler = _import_lambda("s3_event_handler")
        record = {
            "eventName": "ObjectCreated:Put",
            "s3": {
                "bucket": {"name": "biomate-data"},
                "object": {"key": "results/out.csv", "size": 0},
            },
        }
        with (
            patch.object(s3_event_handler, "_get_object_tags",
                         return_value={"user_id": "u1", "workflow_id": "wf1"}),
            patch.object(s3_event_handler, "_get_object_size", return_value=1024) as mock_head,
            patch.object(s3_event_handler, "_notify_billing"),
        ):
            s3_event_handler._process_record(record)
        mock_head.assert_called_once()

    def test_negative_size_is_rejected(self):
        """
        Negative size must be rejected — billing for negative bytes
        would produce impossible costs and Redis ledger corruption.
        """
        mock_notify = self._process_record(-1)
        mock_notify.assert_not_called()

    def test_exabyte_size_is_rejected(self):
        """
        BUG: AWS SDK bug returning INT_MAX would be accepted and billed.
        Fix: reject size > 5 TiB (S3's max single-object size).
        """
        _5_TB_PLUS_1 = 5 * 1024**4 + 1
        mock_notify = self._process_record(_5_TB_PLUS_1)
        mock_notify.assert_not_called()

    def test_exactly_5tib_is_accepted(self):
        """5 TiB is the S3 maximum — must be accepted."""
        _5_TIB = 5 * 1024**4
        mock_notify = self._process_record(_5_TIB)
        mock_notify.assert_called_once()


# ---------------------------------------------------------------------------
# 6.  batch_submitter — new input validation regressions
# ---------------------------------------------------------------------------

class TestBatchSubmitterRegressions(unittest.TestCase):

    def _make_spec(self, **overrides):
        from galaxy.ai.billing.batch_submitter import BatchJobSpec
        defaults = dict(
            user_id="u1", workflow_id="wf1",
            job_name="test", job_queue="q", job_definition="def:1",
            vcpus=2, memory_mb=4096, gpu_count=0,
            instance_type="c6i.large", expected_duration_minutes=30,
        )
        defaults.update(overrides)
        return BatchJobSpec(**defaults)

    def test_invalid_env_var_name_raises_value_error(self):
        """
        BUG: Environment variable names like "INVALID-NAME" were passed through
        unchecked. AWS Batch then rejects the entire job after quota was reserved,
        leaving the reservation permanently leaked.
        Fix: validate names before calling AWS Batch.
        """
        from galaxy.ai.billing.batch_submitter import submit_batch_job
        spec = self._make_spec(environment={"INVALID-NAME": "value"})

        with (
            patch("galaxy.ai.billing.batch_submitter._get_batch"),
            patch("galaxy.ai.billing.batch_submitter.check_and_reserve"),
            patch("galaxy.ai.billing.batch_submitter.estimate_job_cost", return_value=0.01),
        ):
            with pytest.raises(ValueError, match="invalid"):
                submit_batch_job(spec)

    def test_valid_env_var_names_accepted(self):
        """Valid names like MY_VAR, _PRIV, ABC123 must be accepted."""
        from galaxy.ai.billing.batch_submitter import submit_batch_job
        mock_batch = MagicMock()
        mock_batch.submit_job.return_value = {"jobId": "j-ok"}
        spec = self._make_spec(
            environment={"MY_VAR": "x", "_PRIV": "y", "ABC123": "z"}
        )
        with (
            patch("galaxy.ai.billing.batch_submitter._get_batch", return_value=mock_batch),
            patch("galaxy.ai.billing.batch_submitter.check_and_reserve"),
            patch("galaxy.ai.billing.batch_submitter.estimate_job_cost", return_value=0.01),
        ):
            job_id = submit_batch_job(spec)
        assert job_id == "j-ok"

    def test_estimate_job_cost_exception_uses_fargate_fallback(self):
        """
        BUG: If estimate_job_cost raises (e.g., pricing table miss), no fallback
        existed — the job submission would fail with an unexpected exception rather
        than continuing with a conservative Fargate-rate estimate.
        Fix: catch exception and compute Fargate fallback.
        """
        from galaxy.ai.billing.batch_submitter import submit_batch_job
        mock_batch = MagicMock()
        mock_batch.submit_job.return_value = {"jobId": "j-fallback"}

        # estimate_job_cost raises; check_and_reserve should still be called
        with (
            patch("galaxy.ai.billing.batch_submitter._get_batch", return_value=mock_batch),
            patch("galaxy.ai.billing.batch_submitter.check_and_reserve") as mock_reserve,
            patch("galaxy.ai.billing.batch_submitter.estimate_job_cost",
                  side_effect=Exception("unexpected pricing error")),
        ):
            job_id = submit_batch_job(self._make_spec())

        assert job_id == "j-fallback", "Job should still submit using fallback estimate"
        mock_reserve.assert_called_once()
        # The fallback estimate must be a positive float
        args, kwargs = mock_reserve.call_args
        estimated = kwargs.get("estimated_cost_usd") or (args[1] if len(args) > 1 else None)
        assert estimated is not None and estimated > 0, (
            f"Fallback estimate should be positive, got {estimated}"
        )


# ---------------------------------------------------------------------------
# 7.  Lago client — idempotency key uniqueness
# ---------------------------------------------------------------------------

class TestLagoIdempotencyRegressions(unittest.TestCase):
    """
    BUG: transaction_id used int(timestamp) — two LLM calls within the same second
    produce identical transaction_ids, causing Lago to deduplicate them and
    silently drop the second charge.
    Fix: append uuid4 suffix so each call is globally unique.
    """

    def test_two_llm_calls_produce_distinct_transaction_ids(self):
        """Calling emit_llm twice must produce 4 unique transaction IDs."""
        from galaxy.ai.billing.core.lago_client import LagoClient

        sent_events = []

        class FakeLagoClient(LagoClient):
            def __init__(self):
                self._base = "http://fake"
                self._headers = {}
                self._client = None

            def send_batch_events(self, events):
                sent_events.extend(events)
                return len(events)

        client = FakeLagoClient()
        client.emit_llm("u1", "session-1", 1000, 500, "claude-sonnet-4-5-20250929")
        client.emit_llm("u1", "session-1", 1000, 500, "claude-sonnet-4-5-20250929")

        assert len(sent_events) == 4, f"Expected 4 events, got {len(sent_events)}"

        ids = [e.transaction_id for e in sent_events]
        assert len(ids) == len(set(ids)), (
            f"Duplicate transaction_ids detected: {ids}. "
            f"Two same-second calls will be deduplicated by Lago."
        )


# ---------------------------------------------------------------------------
# 8.  LLM client — all providers emit billing
# ---------------------------------------------------------------------------

class TestLLMClientBillingCoverage(unittest.TestCase):
    """
    BUG: Only _generate_anthropic() called _emit_llm_billing().
    OpenAI, Gemini, Ollama, Zhipu, DeepSeek, and Local providers
    silently dropped all cost data.
    Fix: all providers call _emit_llm_billing() after a successful response.
    """

    def _run_provider(self, provider: str, model: str,
                      mock_response: dict, response_text: str) -> list:
        """Run a provider generate call and return captured _emit_llm_billing calls."""
        import asyncio
        from galaxy.ai.billing.core.cost_calculator import CostCalculator

        billing_calls = []

        def fake_emit(user_id, session_id, model, input_tokens, output_tokens, duration_ms):
            billing_calls.append({
                "user_id": user_id,
                "input_tokens": input_tokens,
                "output_tokens": output_tokens,
            })

        from galaxy.ai.ai_assistant import AIConfig
        from galaxy.ai.llm_client import LLMClient

        config = AIConfig()
        config.llm_provider = provider
        config.llm_model = model
        config.llm_api_key = "test-key"
        config.llm_base_url = ""

        client = LLMClient(config)
        client.user_id = "user-billing-test"

        import httpx
        mock_resp = MagicMock(spec=httpx.Response)
        mock_resp.status_code = 200
        mock_resp.json.return_value = mock_response

        # Build a proper async context manager mock for httpx.AsyncClient
        mock_session = MagicMock()
        mock_session.post = AsyncMock(return_value=mock_resp)
        mock_httpx_cls = MagicMock()
        mock_httpx_cls.return_value.__aenter__ = AsyncMock(return_value=mock_session)
        mock_httpx_cls.return_value.__aexit__ = AsyncMock(return_value=False)

        with (
            patch("galaxy.ai.llm_client._emit_llm_billing", side_effect=fake_emit),
            patch("httpx.AsyncClient", mock_httpx_cls),
        ):
            asyncio.run(client.generate_async("test prompt"))

        return billing_calls

    def test_openai_emits_billing(self):
        billing = self._run_provider(
            provider="openai",
            model="gpt-4o",
            mock_response={
                "choices": [{"message": {"content": "hello"}}],
                "usage": {"prompt_tokens": 100, "completion_tokens": 50},
            },
            response_text="hello",
        )
        assert len(billing) >= 1, "OpenAI provider did not emit billing"
        assert billing[0]["input_tokens"] == 100
        assert billing[0]["output_tokens"] == 50

    def test_gemini_emits_billing(self):
        billing = self._run_provider(
            provider="gemini",
            model="gemini-1.5-pro",
            mock_response={
                "candidates": [{"content": {"parts": [{"text": "hello"}]}}],
                "usageMetadata": {"promptTokenCount": 200, "candidatesTokenCount": 80},
            },
            response_text="hello",
        )
        assert len(billing) >= 1, "Gemini provider did not emit billing"
        assert billing[0]["input_tokens"] == 200
        assert billing[0]["output_tokens"] == 80

    def test_ollama_emits_billing(self):
        billing = self._run_provider(
            provider="ollama",
            model="qwen3:32b",
            mock_response={
                "choices": [{"message": {"content": "hello"}}],
                "usage": {"prompt_tokens": 50, "completion_tokens": 30},
            },
            response_text="hello",
        )
        assert len(billing) >= 1, "Ollama provider did not emit billing"

    def test_billing_not_emitted_when_user_id_empty(self):
        """_emit_llm_billing must short-circuit when user_id is empty string."""
        from galaxy.ai.llm_client import _emit_llm_billing

        cost_service_calls = []
        with patch(
            "galaxy.ai.llm_client._emit_llm_billing",
            wraps=_emit_llm_billing,
        ):
            with patch(
                "galaxy.ai.billing.core.realtime_cost_service.get_cost_service"
            ) as mock_svc:
                _emit_llm_billing(
                    user_id="",
                    session_id="s1",
                    model="claude-sonnet-4-5-20250929",
                    input_tokens=1000,
                    output_tokens=500,
                    duration_ms=200.0,
                )
                # cost service should never be called for empty user_id
                mock_svc.assert_not_called()


class TestJavaBillingClientWalletAdapter(unittest.TestCase):
    """
    Tests for the 2026-06-10 wallet/plan adapter. The colleague's
    billing_system Java service refactor removed three endpoints biomate
    used to call:
      - POST /api/billing/quota/acquire / release  (QuotaController deleted)
      - GET  /api/billing/usage/current             (replaced by /usage/summary)
      - GET  /api/billing/quota/usage               (replaced by customers/{id}/wallet)
    JavaBillingClient was adapted to the new surface; these tests lock in
    the mapping so future drift is caught.
    """

    def setUp(self):
        from galaxy.ai.billing.java_billing_client import JavaBillingClient
        self.client = JavaBillingClient(base_url="http://localhost:9999")

    def test_acquire_quota_is_noop_returning_true(self):
        with patch.object(self.client, "_post") as mp:
            ok = self.client.acquire_quota("u1", "gpu_l40", "job-123")
            self.assertTrue(ok)
            mp.assert_not_called()

    def test_release_quota_is_noop_returning_true(self):
        with patch.object(self.client, "_post") as mp:
            ok = self.client.release_quota("u1", "gpu_l40", "job-123")
            self.assertTrue(ok)
            mp.assert_not_called()

    def test_get_current_usage_routes_to_summary_with_month_to_date(self):
        from datetime import date
        with patch.object(self.client, "_get") as mg:
            mg.return_value = {"fromDate": "x", "byCode": []}
            self.client.get_current_usage("u1")
            mg.assert_called_once()
            path, params = mg.call_args.args
            self.assertEqual(path, "/api/billing/usage/summary")
            self.assertEqual(params["externalCustomerId"], "bm_u1")
            today = date.today()
            self.assertEqual(params["startDate"], today.replace(day=1).isoformat())
            self.assertEqual(params["endDate"], today.isoformat())

    def test_get_quota_routes_to_customer_wallet(self):
        with patch.object(self.client, "_get") as mg:
            mg.return_value = {"balanceUsd": 12.34, "grantedUsd": 0.0}
            self.client.get_quota("u1")
            mg.assert_called_once()
            path, params = mg.call_args.args
            self.assertEqual(path, "/api/billing/customers/bm_u1/wallet")
            self.assertEqual(params, {})


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    unittest.main(verbosity=2)
