"""
Billing API — auto-discovered by Galaxy's include_all_package_routers().

Mounts all routes from lib/galaxy/ai/billing/api/billing_router.py.

Public endpoints (JWT auth):
  GET  /api/billing/usage
  GET  /api/billing/usage/history
  GET  /api/billing/quota
  GET  /api/billing/jobs/running

Internal endpoints (X-Internal-Key header):
  POST /internal/billing/job_started
  POST /internal/billing/job_completed
  POST /internal/billing/s3_put
  POST /internal/billing/s3_delete

Lago webhook:
  POST /webhooks/lago
"""

import logging as _logging

_log = _logging.getLogger(__name__)

try:
    from galaxy.ai.billing.api.billing_router import router  # noqa: F401 — picked up by include_all_package_routers
except (ImportError, RuntimeError) as _e:
    _log.warning(
        "Full billing router unavailable (%s: %s). "
        "Billing endpoints are served by billing_lite.py instead. "
        "Set LAGO_API_KEY env var to enable Lago metering.",
        type(_e).__name__,
        _e,
    )
    # Provide a no-op router so Galaxy's router scanner doesn't crash
    from fastapi import APIRouter as _APIRouter
    router = _APIRouter()
