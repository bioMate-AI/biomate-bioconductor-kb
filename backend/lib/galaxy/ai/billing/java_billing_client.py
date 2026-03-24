"""
Java Billing Service Client for BioMate

Forwards usage events to the Java Spring Boot billing microservice which owns:
  - Lago (metering + invoicing)
  - Stripe (payment processing)
  - PostgreSQL (event journal)
  - Prometheus → Grafana (observability)

All methods are fire-and-forget: they log on failure and never raise,
so billing issues never block user-facing requests.

Configuration (env vars):
  JAVA_BILLING_SERVICE_URL  — base URL of the Java service (e.g. http://35.86.137.71:8080)
  JAVA_BILLING_ENABLED      — set "true" to activate; default "false"
"""

import os
import time
import uuid
import logging
from datetime import date
from typing import Optional

import httpx

log = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

JAVA_BILLING_URL: str = os.environ.get("JAVA_BILLING_SERVICE_URL", "").rstrip("/")
JAVA_BILLING_ENABLED: bool = os.environ.get("JAVA_BILLING_ENABLED", "false").lower() == "true"

_TIMEOUT = 5.0          # seconds — generous but bounded
_RETRY_DELAYS = (1.0, 2.0, 4.0)   # exponential backoff on transient errors


# ---------------------------------------------------------------------------
# externalId convention — single place to change when Q1 is answered
# ---------------------------------------------------------------------------

def external_id(user_id: str) -> str:
    """Map a BioMate user_id to the externalCustomerId used in the Java service.

    Current convention: "bm_{user_id}" (prefix avoids collisions with other tenants).
    Change the return value here when Q1 (externalId format) is decided.
    """
    return f"bm_{user_id}"


# ---------------------------------------------------------------------------
# Client
# ---------------------------------------------------------------------------

class JavaBillingClient:
    """
    Thin httpx wrapper around the Java billing service REST API.
    Mirrors the LagoClient pattern: singleton, connection pooling, retry on
    transient network errors, fire-and-forget semantics.
    """

    def __init__(self, base_url: str = JAVA_BILLING_URL):
        self._base = base_url
        self._client = httpx.Client(
            base_url=self._base,
            headers={"Content-Type": "application/json"},
            timeout=_TIMEOUT,
        )

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _post(self, path: str, payload: dict) -> bool:
        """POST with retry. Returns True on success, False on any failure."""
        last_exc: Exception = RuntimeError("no attempts made")
        for attempt, delay in enumerate(_RETRY_DELAYS):
            try:
                r = self._client.post(path, json=payload)
                if r.status_code in (200, 201):
                    return True
                # 4xx errors are not retried — log and bail
                body = r.json() if r.headers.get("content-type", "").startswith("application/json") else r.text[:200]
                log.warning("[java_billing] POST %s → %s %s", path, r.status_code, body)
                return False
            except (httpx.TimeoutException, httpx.ConnectError) as exc:
                last_exc = exc
                if attempt + 1 < len(_RETRY_DELAYS):
                    log.warning("[java_billing] POST %s attempt %d/%d: %s — retrying in %.1fs",
                                path, attempt + 1, len(_RETRY_DELAYS), exc, delay)
                    time.sleep(delay)
                else:
                    log.error("[java_billing] POST %s failed after %d attempts: %s",
                              path, len(_RETRY_DELAYS), exc)
            except Exception as exc:
                log.error("[java_billing] POST %s unexpected error: %s", path, exc)
                return False
        return False

    def _get(self, path: str, params: dict) -> Optional[dict]:
        """GET with single attempt. Returns parsed data dict or None on failure."""
        try:
            r = self._client.get(path, params=params)
            if r.status_code == 200:
                envelope = r.json()
                if envelope.get("code") == 0:
                    return envelope.get("data")
            log.warning("[java_billing] GET %s → %s", path, r.status_code)
            return None
        except Exception as exc:
            log.error("[java_billing] GET %s error: %s", path, exc)
            return None

    # ------------------------------------------------------------------
    # Customer registration
    # ------------------------------------------------------------------

    def register_customer(
        self,
        user_id: str,
        name: str,
        email: str,
        currency: str = "USD",
    ) -> bool:
        """Create or update a customer in the Java billing service.

        New customers are auto-subscribed to the default Lago plan.
        Idempotent — safe to call on every login or re-registration.
        """
        ok = self._post("/api/billing/customers", {
            "externalId": external_id(user_id),
            "name": name,
            "email": email,
            "currency": currency,
        })
        if ok:
            log.info("[java_billing] customer registered: user_id=%s ext_id=%s",
                     user_id, external_id(user_id))
        return ok

    # ------------------------------------------------------------------
    # Usage events
    # ------------------------------------------------------------------

    def emit_llm(
        self,
        user_id: str,
        model: str,
        input_tokens: int,
        output_tokens: int,
        transaction_id: Optional[str] = None,
    ) -> bool:
        """Report an LLM API call to the billing service.

        Current schema: combined token count (input + output) as a single "llm" event.
        To split into separate input/output events when Q2 is decided, change only
        this method — callers stay unchanged.
        """
        tid = transaction_id or f"llm-{user_id}-{uuid.uuid4().hex[:12]}"
        total_tokens = input_tokens + output_tokens
        ok = self._post("/api/billing/usage/events", {
            "externalCustomerId": external_id(user_id),
            "code": "llm",
            "transactionId": tid,
            "timestamp": time.time(),
            "properties": {
                "model": model,
                "value": str(total_tokens),
                # Keep breakdown in properties for future use
                "input_tokens": str(input_tokens),
                "output_tokens": str(output_tokens),
            },
        })
        if ok:
            log.info("[java_billing] llm event sent: user=%s model=%s tokens=%d",
                     user_id, model, total_tokens)
        return ok

    def emit_ec2(
        self,
        user_id: str,
        instance_type: str,
        region: str,
        duration_seconds: float,
        transaction_id: Optional[str] = None,
    ) -> bool:
        """Report AWS EC2/Batch compute usage. Java service converts to Credits."""
        tid = transaction_id or f"ec2-{user_id}-{uuid.uuid4().hex[:12]}"
        ok = self._post("/api/billing/usage/events", {
            "externalCustomerId": external_id(user_id),
            "code": "ec2_instance",
            "transactionId": tid,
            "timestamp": time.time(),
            "properties": {
                "instanceType": instance_type,
                "region": region,
                "value": str(int(duration_seconds)),
            },
        })
        if ok:
            log.info("[java_billing] ec2 event sent: user=%s type=%s region=%s sec=%.0f",
                     user_id, instance_type, region, duration_seconds)
        return ok

    def emit_ebs(
        self,
        user_id: str,
        volume_type: str,
        size_gb: float,
        duration_seconds: float,
        transaction_id: Optional[str] = None,
    ) -> bool:
        """Report AWS S3/EBS storage usage. Java service converts to Credits."""
        tid = transaction_id or f"ebs-{user_id}-{uuid.uuid4().hex[:12]}"
        ok = self._post("/api/billing/usage/events", {
            "externalCustomerId": external_id(user_id),
            "code": "ebs_storage",
            "transactionId": tid,
            "timestamp": time.time(),
            "properties": {
                "volumeType": volume_type,
                "sizeGb": str(int(size_gb)) if size_gb >= 1 else "1",
                "value": str(int(duration_seconds)),
            },
        })
        if ok:
            log.info("[java_billing] ebs event sent: user=%s type=%s size_gb=%.1f sec=%.0f",
                     user_id, volume_type, size_gb, duration_seconds)
        return ok

    # ------------------------------------------------------------------
    # Quota (concurrent resource slots)
    # ------------------------------------------------------------------

    def acquire_quota(self, user_id: str, spec_code: str, resource_id: str) -> bool:
        """Acquire a concurrent resource slot before starting a job.

        Call before submitting a Nextflow/Batch run.
        Always call release_quota() in the completion/failure path.
        """
        return self._post("/api/billing/quota/acquire", {
            "externalCustomerId": external_id(user_id),
            "specCode": spec_code,
            "resourceId": resource_id,
        })

    def release_quota(self, user_id: str, spec_code: str, resource_id: str) -> bool:
        """Release a concurrent resource slot after a job ends (idempotent)."""
        return self._post("/api/billing/quota/release", {
            "externalCustomerId": external_id(user_id),
            "specCode": spec_code,
            "resourceId": resource_id,
        })

    # ------------------------------------------------------------------
    # Query endpoints (used for proxying to frontend)
    # ------------------------------------------------------------------

    def get_current_usage(self, user_id: str) -> Optional[dict]:
        """Fetch current billing period usage from Java service (live from Lago)."""
        return self._get(
            "/api/billing/usage/current",
            {"externalCustomerId": external_id(user_id)},
        )

    def get_usage_summary(
        self,
        user_id: str,
        start_date: str,   # "YYYY-MM-DD"
        end_date: str,     # "YYYY-MM-DD"
    ) -> Optional[dict]:
        """Fetch usage summary with daily trend data."""
        return self._get(
            "/api/billing/usage/summary",
            {
                "externalCustomerId": external_id(user_id),
                "startDate": start_date,
                "endDate": end_date,
            },
        )

    def get_usage_details(
        self,
        user_id: str,
        start_date: str,
        end_date: str,
        page: int = 0,
        size: int = 20,
    ) -> Optional[dict]:
        """Fetch paginated event-level detail from Java service local DB."""
        return self._get(
            "/api/billing/usage/details",
            {
                "externalCustomerId": external_id(user_id),
                "startDate": start_date,
                "endDate": end_date,
                "page": page,
                "size": size,
            },
        )

    def get_quota(self, user_id: str) -> Optional[dict]:
        """Fetch plan quota limits and current usage from Java service."""
        return self._get(
            "/api/billing/quota/usage",
            {"externalCustomerId": external_id(user_id)},
        )

    def get_invoices(
        self,
        user_id: str,
        page: int = 0,
        per_page: int = 10,
    ) -> Optional[dict]:
        """Fetch invoice list for a user (cached from Lago)."""
        return self._get(
            "/api/billing/invoices",
            {
                "externalCustomerId": external_id(user_id),
                "page": page,
                "perPage": per_page,
            },
        )

    def close(self) -> None:
        self._client.close()


# ---------------------------------------------------------------------------
# Module-level singleton
# ---------------------------------------------------------------------------

_client: Optional[JavaBillingClient] = None


def get_java_billing_client() -> Optional[JavaBillingClient]:
    """Return the singleton JavaBillingClient, or None if not enabled.

    Returns None when JAVA_BILLING_ENABLED is not "true" or when
    JAVA_BILLING_SERVICE_URL is not set — callers must guard with `if jbc:`.
    """
    global _client
    if not JAVA_BILLING_ENABLED or not JAVA_BILLING_URL:
        return None
    if _client is None:
        _client = JavaBillingClient()
        log.info("[java_billing] client initialised → %s", JAVA_BILLING_URL)
    return _client
