"""
User Domain Taxonomy
====================
Re-exports from domain_registry.py for backward compatibility.

CANONICAL SOURCE OF TRUTH: backend/lib/galaxy/ai/domain_registry.py
Do not add domain definitions here — add them to domain_registry.py.
"""

from typing import List

from .domain_registry import (
    CANONICAL_DOMAINS,
    DOMAIN_LABELS,
    DOMAIN_TOPICS as DOMAIN_TAXONOMY,
    get_topics_for_domains as _get_topics,
)

# Re-export under the names callers expect
__all__ = ["DOMAIN_TAXONOMY", "DOMAIN_LABELS", "get_topics_for_domains"]


def get_topics_for_domains(domains: List[str]) -> List[str]:
    """Return all topics for the selected domains, deduplicated (order-preserving)."""
    return _get_topics(domains)
