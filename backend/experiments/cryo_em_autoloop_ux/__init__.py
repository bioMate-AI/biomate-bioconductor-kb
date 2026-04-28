"""
CryoEM Auto-Loop UX — knowledge-enriched loop with rich progress reporting.

Imports:
    from cryo_em_autoloop_ux import UXAwareAutoLoop, ProgressReporter
    from cryo_em_autoloop_ux import KnowledgeEnrichedTuner, EnrichedRemediation
    from cryo_em_autoloop_ux.knowledge_base import GATE_KNOWLEDGE, get_knowledge, KnowledgeEntry
    from cryo_em_autoloop_ux.forum_knowledge import FORUM_ENTRIES, ENTRIES_BY_GATE, ForumEntry
"""

from .ux_loop import UXAwareAutoLoop
from .progress_reporter import ProgressReporter
from .enriched_tuner import KnowledgeEnrichedTuner, EnrichedRemediation
from .knowledge_base import GATE_KNOWLEDGE, get_knowledge, KnowledgeEntry
from .forum_knowledge import FORUM_ENTRIES, ENTRIES_BY_GATE, ForumEntry

__all__ = [
    "UXAwareAutoLoop",
    "ProgressReporter",
    "KnowledgeEnrichedTuner",
    "EnrichedRemediation",
    "GATE_KNOWLEDGE",
    "get_knowledge",
    "KnowledgeEntry",
    "FORUM_ENTRIES",
    "ENTRIES_BY_GATE",
    "ForumEntry",
]
