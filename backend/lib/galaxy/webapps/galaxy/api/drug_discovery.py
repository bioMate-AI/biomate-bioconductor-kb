"""
Drug Discovery API — auto-discovered by Galaxy's include_all_package_routers().

Mounts all routes from lib/galaxy/ai/drug_discovery/api_router.py.

Endpoints:
  POST /api/drug-discovery/{campaign_id}/ingest-assay
  GET  /api/drug-discovery/{campaign_id}/compounds
  GET  /api/drug-discovery/{campaign_id}/export/cro-order
  POST /api/drug-discovery/{campaign_id}/models/register
  GET  /api/drug-discovery/{campaign_id}/models
  POST /api/drug-discovery/{campaign_id}/models/{model_name}/run
  GET  /api/drug-discovery/availability
"""

from galaxy.ai.drug_discovery.api_router import router  # noqa: F401 — picked up by include_all_package_routers
