"""
Customer Feedback API — auto-discovered by Galaxy's include_all_package_routers().

Mounts the routes from lib/galaxy/ai/drug_discovery/feedback_router.py
defined for the IND Report customer-product feedback loop (Appendix B of
docs/20260504_IND_PRODUCT_UI_REQUIREMENTS.md).

Endpoints:
  POST /api/ind-report/projects/{id}/edit         — capture paragraph edit
  POST /api/ind-report/audit/{finding_id}/dismiss — capture dismissal + reason
  POST /api/ind-report/citations/suggest          — citation suggestion
  POST /api/ind-report/sections/{id}/regenerate   — regenerate-with-instruction
  GET  /api/regulatory/feedback/queue             — internal review queue
  GET  /api/regulatory/active_adapter             — active LoRA adapter info
"""

from galaxy.ai.drug_discovery.feedback_router import router  # noqa: F401 — picked up by include_all_package_routers
