"""IND Report action endpoints — auto-discovered via Galaxy's
include_all_package_routers().

Mounts the routes from lib/galaxy/ai/drug_discovery/ind_actions_router.py:

  POST /api/ind-report/projects/{id}/sign           — 21 CFR Part 11 e-signature
  POST /api/ind-report/projects/{id}/document.md    — Markdown export

Separate from feedback_router.py to keep the high-churn feedback file from
absorbing infrastructure additions during automation sweeps.
"""

from galaxy.ai.drug_discovery.ind_actions_router import router  # noqa: F401
