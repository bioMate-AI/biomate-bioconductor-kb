"""
Regulatory LLM streaming API — auto-discovered by Galaxy's
include_all_package_routers().

Mounts the routes from lib/galaxy/ai/drug_discovery/llm_streaming_router.py:

  POST /api/regulatory/generate_smoke   — blocking smoke (PI-12)
  POST /api/regulatory/generate_stream  — SSE phase events + token streaming

The streaming endpoint is what the IND Report UI's Regenerate button calls
in production so the customer sees real progress while the model works,
instead of staring at 30-80s of silence.
"""

from galaxy.ai.drug_discovery.llm_streaming_router import router  # noqa: F401
