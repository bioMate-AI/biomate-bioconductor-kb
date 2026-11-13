"""Root pytest hooks for BioMate backend.

Stub sentence_transformers + unified_workflow_search before any test imports
AIAssistant. Developer laptops often have a broken sentence_transformers →
sklearn → scipy ABI chain that SIGFPEs / TypeErrors on import; production
images are fine. Param-projection unit tests do not need embeddings.
"""
from __future__ import annotations

import sys
import types

if "sentence_transformers" not in sys.modules:
    _st = types.ModuleType("sentence_transformers")
    _st.SentenceTransformer = type("SentenceTransformer", (), {})
    sys.modules["sentence_transformers"] = _st

if "galaxy.ai.unified_workflow_search" not in sys.modules:
    _uws = types.ModuleType("galaxy.ai.unified_workflow_search")
    _uws.UnifiedWorkflowSearch = type("UnifiedWorkflowSearch", (), {})
    _uws.get_workflow_search = lambda *a, **k: None  # type: ignore[assignment]
    _uws.WorkflowMatch = type("WorkflowMatch", (), {})
    sys.modules["galaxy.ai.unified_workflow_search"] = _uws
