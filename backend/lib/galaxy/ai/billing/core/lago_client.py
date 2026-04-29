"""
Lago Billing Client for BioMate

Wraps Lago's REST API to:
  1. Send usage events (metered consumption per user)
  2. Manage customer accounts
  3. Query current-period usage and wallet balance
  4. Trigger alerts (via Lago webhooks, registered separately)

Lago billable metrics expected to be pre-configured in Lago UI or Terraform:
  - llm_input_tokens      (field_name: tokens, aggregation: SUM)
  - llm_output_tokens     (field_name: tokens, aggregation: SUM)
  - batch_vcpu_seconds    (field_name: seconds, aggregation: SUM)
  - batch_gpu_seconds     (field_name: seconds, aggregation: SUM)
  - batch_memory_gb_sec   (field_name: gb_seconds, aggregation: SUM)
  - s3_storage_gb_hours   (field_name: gb_hours, aggregation: SUM)
  - s3_put_requests       (field_name: count, aggregation: COUNT)
  - s3_get_requests       (field_name: count, aggregation: COUNT)
  - s3_data_transfer_gb   (field_name: gb, aggregation: SUM)
"""

import os
import time
import uuid
import logging
from typing import Optional
from dataclasses import dataclass

import httpx

log = logging.getLogger(__name__)

# Environment configuration
_ALLOW_INSECURE_DEV_MODE = os.environ.get("BILLING_DEV_MODE", "").lower() == "true"

LAGO_BASE_URL = os.environ.get("LAGO_API_URL", "http://lago:3000")

def _resolve_lago_api_key() -> str:
    # 1. Env var takes priority — dev machines and unit tests work without SM
    key = os.environ.get("LAGO_API_KEY", "")
    if key:
        return key
    # 2. Dev mode bypass
    if _ALLOW_INSECURE_DEV_MODE:
        log.warning("BILLING_DEV_MODE enabled: using insecure default LAGO_API_KEY")
        return "dev-insecure-lago-key"
    # 3. Secrets Manager (production)
    try:
        import boto3, functools
        @functools.lru_cache(maxsize=None)
        def _fetch():
            sm = boto3.client("secretsmanager",
                              region_name=os.environ.get("AWS_REGION", "us-west-2"))
            return sm.get_secret_value(SecretId="biomate/lago/api-key")["SecretString"]
        return _fetch()
    except Exception as e:
        raise RuntimeError(
            f"LAGO_API_KEY not set and Secrets Manager fetch failed: {e}. "
            "Set LAGO_API_KEY env var or ensure the Lambda role has secretsmanager:GetSecretValue."
        ) from e

LAGO_API_KEY = _resolve_lago_api_key()
LAGO_TIMEOUT = 5.0  # seconds; fire-and-forget pattern, don't block requests

# Exponential backoff delays for transient network errors (1s, 2s, 4s)
_RETRY_DELAYS: tuple[float, ...] = (1.0, 2.0, 4.0)


# ---------------------------------------------------------------------------
# Event codes — must match exactly what is configured in Lago
# ---------------------------------------------------------------------------
class EventCode:
    LLM                 = "llm"
    LLM_INPUT_TOKENS    = "llm_input_tokens"
    LLM_OUTPUT_TOKENS   = "llm_output_tokens"
    BATCH_VCPU_SECONDS  = "batch_vcpu_seconds"
    BATCH_GPU_SECONDS   = "batch_gpu_seconds"
    BATCH_MEM_GB_SEC    = "batch_memory_gb_sec"
    S3_STORAGE_GB_HR    = "s3_storage_gb_hours"
    S3_PUT_REQUESTS     = "s3_put_requests"
    S3_GET_REQUESTS     = "s3_get_requests"
    S3_DATA_TRANSFER_GB = "s3_data_transfer_gb"


def external_customer_id(user_id: str) -> str:
    """Deterministic Lago external_id for a user — must match Java billing service convention.
    Format: bm_{user_id}  (prefix avoids collisions with other tenants).
    """
    return f"bm_{user_id}" if not user_id.startswith("bm_") else user_id


def subscription_id(user_id: str, plan_code: str = "base") -> str:
    """Deterministic subscription external_id for a user.
    Format: bm_{user_id}_{plan_code} — must match what the Java billing service creates.
    Java CustomerService.java: subscriptionId = externalId + "_" + defaultPlan
    """
    ext_id = external_customer_id(user_id)
    return f"{ext_id}_{plan_code}"


@dataclass
class LagoEvent:
    transaction_id: str            # globally unique; used for idempotency
    external_subscription_id: str  # links event to the right subscription (required by Lago v1.44+)
    code: str                      # EventCode.*
    timestamp: float               # Unix epoch (float)
    properties: dict               # {"tokens": 1234} — field matching metric config


class LagoClient:
    """
    Thin async-ready wrapper around Lago REST API.
    Uses httpx with connection pooling.

    Recommended usage: one singleton shared across the application.
    """

    def __init__(
        self,
        api_url: str = LAGO_BASE_URL,
        api_key: str = LAGO_API_KEY,
    ):
        self._base = api_url.rstrip("/")
        self._headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        }
        self._client = httpx.Client(
            base_url=self._base,
            headers=self._headers,
            timeout=LAGO_TIMEOUT,
        )

    # -----------------------------------------------------------------------
    # Internal: retry helper
    # -----------------------------------------------------------------------

    def _retry_post(self, url: str, **kwargs) -> httpx.Response:
        """
        POST with exponential backoff on transient network errors.
        Retries up to len(_RETRY_DELAYS) times on TimeoutException or ConnectError.
        HTTP error responses (4xx/5xx) are returned immediately — no retry.
        Raises the last exception if all attempts fail.
        """
        last_exc: Exception = RuntimeError("no attempts made")
        for attempt, delay in enumerate(_RETRY_DELAYS):
            try:
                return self._client.post(url, **kwargs)
            except (httpx.TimeoutException, httpx.ConnectError) as exc:
                last_exc = exc
                if attempt + 1 < len(_RETRY_DELAYS):
                    log.warning(
                        "Lago POST %s attempt %d/%d: %s — retrying in %.1fs",
                        url, attempt + 1, len(_RETRY_DELAYS), exc, delay,
                    )
                    time.sleep(delay)
                else:
                    log.error("Lago POST %s failed after %d attempts: %s",
                              url, len(_RETRY_DELAYS), exc)
        raise last_exc

    # -----------------------------------------------------------------------
    # Events
    # -----------------------------------------------------------------------

    def send_event(self, event: LagoEvent) -> bool:
        """
        POST /api/v1/events
        Returns True on success; logs and returns False on failure.
        This should NOT raise — billing failures must never block user requests.
        Retries up to 3 times on transient network errors.
        """
        payload = {
            "event": {
                "transaction_id":           event.transaction_id,
                "external_subscription_id": event.external_subscription_id,
                "code":                     event.code,
                "timestamp":                int(event.timestamp),
                "properties":               event.properties,
            }
        }
        try:
            r = self._retry_post("/api/v1/events", json=payload)
            if r.status_code in (200, 201):
                return True
            log.warning("Lago event rejected %s %s → %s %s",
                        event.code, event.transaction_id, r.status_code, r.text[:200])
            return False
        except Exception as exc:
            log.error("Lago send_event failed: %s", exc)
            return False

    def send_batch_events(self, events: list[LagoEvent]) -> int:
        """
        POST /api/v1/events/batch  (up to 100 events per call)
        Returns number of events successfully accepted.
        Retries up to 3 times on transient network errors.
        """
        payload = {
            "events": [
                {
                    "transaction_id":           e.transaction_id,
                    "external_subscription_id": e.external_subscription_id,
                    "code":                     e.code,
                    "timestamp":                int(e.timestamp),
                    "properties":               e.properties,
                }
                for e in events
            ]
        }
        try:
            r = self._retry_post("/api/v1/events/batch", json=payload)
            if r.status_code in (200, 201):
                return len(events)
            log.warning("Lago batch event rejected: %s %s", r.status_code, r.text[:200])
            return 0
        except Exception as exc:
            log.error("Lago send_batch_events failed: %s", exc)
            return 0

    # -----------------------------------------------------------------------
    # Convenience builders
    # -----------------------------------------------------------------------

    def _sub_id(self, user_id: str, plan_code: str = "base") -> str:
        """Resolve subscription ID for event routing. Uses cached plan when available."""
        return subscription_id(user_id, plan_code)

    def emit_llm(
        self,
        user_id: str,
        session_id: str,
        input_tokens: int,
        output_tokens: int,
        model: str,
        plan_code: str = "base",
    ) -> None:
        ts  = time.time()
        uid = uuid.uuid4().hex[:12]   # unique per invocation; avoids sub-second collisions
        sub = self._sub_id(user_id, plan_code)
        self.send_batch_events([
            LagoEvent(
                transaction_id=f"llm-in-{session_id}-{uid}",
                external_subscription_id=sub,
                code=EventCode.LLM_INPUT_TOKENS,
                timestamp=ts,
                properties={"tokens": input_tokens, "model": model},
            ),
            LagoEvent(
                transaction_id=f"llm-out-{session_id}-{uid}",
                external_subscription_id=sub,
                code=EventCode.LLM_OUTPUT_TOKENS,
                timestamp=ts,
                properties={"tokens": output_tokens, "model": model},
            ),
            LagoEvent(
                transaction_id=f"llm-agg-{session_id}-{uid}",
                external_subscription_id=sub,
                code=EventCode.LLM,
                timestamp=ts,
                properties={
                    "value": input_tokens + output_tokens,
                    "model": model,
                    "session_id": session_id,
                },
            ),
        ])

    def emit_batch_job(
        self,
        user_id: str,
        job_id: str,
        vcpus: float,
        gpu_count: int,
        memory_gb: float,
        duration_seconds: float,
        plan_code: str = "base",
    ) -> None:
        ts = time.time()
        sub = self._sub_id(user_id, plan_code)
        events: list[LagoEvent] = [
            LagoEvent(
                transaction_id=f"batch-vcpu-{job_id}",
                external_subscription_id=sub,
                code=EventCode.BATCH_VCPU_SECONDS,
                timestamp=ts,
                properties={"seconds": round(vcpus * duration_seconds, 3)},
            ),
            LagoEvent(
                transaction_id=f"batch-mem-{job_id}",
                external_subscription_id=sub,
                code=EventCode.BATCH_MEM_GB_SEC,
                timestamp=ts,
                properties={"gb_seconds": round(memory_gb * duration_seconds, 3)},
            ),
        ]
        if gpu_count > 0:
            events.append(LagoEvent(
                transaction_id=f"batch-gpu-{job_id}",
                external_subscription_id=sub,
                code=EventCode.BATCH_GPU_SECONDS,
                timestamp=ts,
                properties={"seconds": round(gpu_count * duration_seconds, 3)},
            ))
        self.send_batch_events(events)

    def emit_s3_put(self, user_id: str, size_bytes: int, key: str, plan_code: str = "base") -> None:
        ts = time.time()
        gb = size_bytes / (1024 ** 3)
        sub = self._sub_id(user_id, plan_code)
        self.send_batch_events([
            LagoEvent(
                transaction_id=f"s3-put-{user_id}-{uuid.uuid4().hex[:8]}",
                external_subscription_id=sub,
                code=EventCode.S3_PUT_REQUESTS,
                timestamp=ts,
                properties={"count": 1, "key": key},
            ),
            LagoEvent(
                transaction_id=f"s3-store-{user_id}-{uuid.uuid4().hex[:8]}",
                external_subscription_id=sub,
                code=EventCode.S3_STORAGE_GB_HR,
                # 30-day default retention converted to GB-hours
                timestamp=ts,
                properties={"gb_hours": round(gb * 24 * 30, 6)},
            ),
        ])

    def emit_s3_get(self, user_id: str, size_bytes: int, key: str, is_cross_region: bool = False, plan_code: str = "base") -> None:
        ts = time.time()
        gb = size_bytes / (1024 ** 3)
        sub = self._sub_id(user_id, plan_code)
        events = [
            LagoEvent(
                transaction_id=f"s3-get-{user_id}-{uuid.uuid4().hex[:8]}",
                external_subscription_id=sub,
                code=EventCode.S3_GET_REQUESTS,
                timestamp=ts,
                properties={"count": 1, "key": key},
            )
        ]
        if is_cross_region and gb > 0:
            events.append(LagoEvent(
                transaction_id=f"s3-xfer-{user_id}-{uuid.uuid4().hex[:8]}",
                external_subscription_id=sub,
                code=EventCode.S3_DATA_TRANSFER_GB,
                timestamp=ts,
                properties={"gb": round(gb, 6)},
            ))
        self.send_batch_events(events)

    # -----------------------------------------------------------------------
    # Customer management
    # -----------------------------------------------------------------------

    def upsert_customer(
        self,
        user_id: str,
        email: str,
        name: str,
        plan_code: str = "base",
        metadata: Optional[dict] = None,
    ) -> bool:
        """Create or update a Lago customer and subscribe to plan (idempotent).
        external_id is always bm_{user_id} to match the Java billing service convention.
        """
        ext_id = external_customer_id(user_id)
        payload = {
            "customer": {
                "external_id": ext_id,
                "email": email,
                "name": name,
                "metadata": [
                    {"key": k, "value": str(v)}
                    for k, v in (metadata or {}).items()
                ],
            }
        }
        try:
            r = self._client.post("/api/v1/customers", json=payload)
            ok = r.status_code in (200, 201)
            if ok:
                # Subscribe to plan using the same subscription_id format as Java service
                self.assign_plan(user_id, plan_code)
            return ok
        except Exception as exc:
            log.error("Lago upsert_customer failed: %s", exc)
            return False

    def assign_plan(self, user_id: str, plan_code: str = "base") -> bool:
        """Subscribe a customer to a plan (idempotent, updates existing subscription).
        Subscription external_id format: bm_{user_id}_{plan_code} — matches Java service.
        """
        ext_id = external_customer_id(user_id)
        sub_id = subscription_id(user_id, plan_code)
        payload = {
            "subscription": {
                "external_customer_id": ext_id,
                "plan_code": plan_code,
                "external_id": sub_id,  # deterministic — matches event routing
            }
        }
        try:
            r = self._client.post("/api/v1/subscriptions", json=payload)
            return r.status_code in (200, 201)
        except Exception as exc:
            log.error("Lago assign_plan failed: %s", exc)
            return False

    # -----------------------------------------------------------------------
    # Wallet / credits
    # -----------------------------------------------------------------------

    def get_wallet_balance(self, user_id: str) -> Optional[float]:
        """Returns the current wallet balance in USD, or None on error."""
        try:
            r = self._client.get(
                f"/api/v1/wallets",
                params={"external_customer_id": user_id},
            )
            data = r.json()
            wallets = data.get("wallets", [])
            if wallets:
                return float(wallets[0].get("balance", 0))
            return 0.0
        except Exception as exc:
            log.error("Lago get_wallet_balance failed: %s", exc)
            return None

    def top_up_wallet(self, wallet_id: str, amount: float) -> bool:
        """Add credits to an existing wallet."""
        payload = {
            "wallet_transaction": {
                "wallet_id": wallet_id,
                "paid_credits": str(round(amount, 2)),
                "granted_credits": "0",
            }
        }
        try:
            r = self._client.post("/api/v1/wallet_transactions", json=payload)
            return r.status_code in (200, 201)
        except Exception as exc:
            log.error("Lago top_up_wallet failed: %s", exc)
            return False

    # -----------------------------------------------------------------------
    # Usage query (current period)
    # -----------------------------------------------------------------------

    def get_current_usage(self, user_id: str) -> Optional[dict]:
        """
        Returns the current-period usage summary from Lago.
        Shape: { "total_amount_cents": int, "charges_usage": [...] }
        """
        try:
            r = self._client.get(
                f"/api/v1/customers/{user_id}/current_usage",
            )
            if r.status_code == 200:
                return r.json().get("customer_usage", {})
            return None
        except Exception as exc:
            log.error("Lago get_current_usage failed: %s", exc)
            return None

    def get_plan_limit_usd(self, plan_code: str) -> Optional[float]:
        """
        Query Lago for the monthly spend limit of a given plan.

        Lago plans can have a `amount_cents` / `amount_currency` field on the
        plan object.  We use this as the quota cap when it is set.

        Returns the limit in USD, or None if the plan is not found or does
        not declare a fixed amount (e.g. pure usage-based plans).
        """
        try:
            r = self._client.get(f"/api/v1/plans/{plan_code}")
            if r.status_code != 200:
                return None
            plan = r.json().get("plan", {})
            amount_cents    = plan.get("amount_cents")
            amount_currency = plan.get("amount_currency", "USD").upper()
            if amount_cents is None:
                return None
            # Convert cents to dollars; only handle USD for now
            if amount_currency != "USD":
                log.warning("Lago plan %s uses currency %s; USD expected", plan_code, amount_currency)
                return None
            return float(amount_cents) / 100.0
        except Exception as exc:
            log.error("Lago get_plan_limit_usd(%s) failed: %s", plan_code, exc)
            return None

    def close(self):
        self._client.close()


# ---------------------------------------------------------------------------
# Module-level singleton
# ---------------------------------------------------------------------------
_lago: Optional[LagoClient] = None

def get_lago_client() -> LagoClient:
    global _lago
    if _lago is None:
        _lago = LagoClient()
    return _lago
