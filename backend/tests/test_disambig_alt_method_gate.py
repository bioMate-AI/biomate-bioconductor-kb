"""Unit tests for the alternative-method disambiguation override.

Covers `_detect_alt_method_enumeration` in
`backend/lib/galaxy/ai/ai_assistant.py`, the intent-driven override that
forces the disambiguation gate to fire when a user query explicitly
enumerates multiple known DE / consensus methods (e.g. "DESeq2 or edgeR").

Background: see `docs/20260612_DISAMBIG_GATE_AUDIT.md` — the score-gap-only
gate almost never fires because BGE dense retrieval returns a single
high-confidence winner.
"""

import os
import sys

# Allow `from galaxy.ai.ai_assistant import ...` without importing the
# heavy AIAssistant class machinery. We only need the module-level helper.
_BACKEND_LIB = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "lib"
)
if _BACKEND_LIB not in sys.path:
    sys.path.insert(0, _BACKEND_LIB)


def _load_helper():
    # Import lazily so test collection doesn't blow up if heavy deps
    # aren't installed in the test env.
    from galaxy.ai.ai_assistant import _detect_alt_method_enumeration
    return _detect_alt_method_enumeration


def test_audit_query_1_deseq2_or_edger_triggers():
    detect = _load_helper()
    methods, is_enum = detect("DESeq2 or edgeR differential expression")
    assert is_enum is True
    assert "deseq2" in methods and "edger" in methods


def test_audit_query_3_compare_three_methods_triggers():
    detect = _load_helper()
    methods, is_enum = detect("compare DESeq2 edgeR limma for RNA-seq")
    assert is_enum is True
    assert set(methods) >= {"deseq2", "edger", "limma"}


def test_generic_de_query_does_not_trigger():
    detect = _load_helper()
    _, is_enum = detect("differential expression analysis")
    assert is_enum is False


def test_single_method_does_not_trigger():
    # Backwards compat: a clear single-method query must still resolve
    # via the high-confidence path, not be redirected to disambig.
    detect = _load_helper()
    methods, is_enum = detect("run DESeq2 on my counts")
    assert methods == ["deseq2"]
    assert is_enum is False


def test_two_methods_without_marker_word_does_not_trigger():
    # "DESeq2 edgeR" alone (no or/vs/compare/and) does NOT enumerate
    # alternatives — could be a pipeline naming both methods used together.
    # The marker word requirement keeps the override narrow.
    detect = _load_helper()
    _, is_enum = detect("DESeq2 edgeR pipeline")
    assert is_enum is False


def test_versus_marker_triggers():
    detect = _load_helper()
    _, is_enum = detect("noiseq vs sleuth single cell")
    assert is_enum is True


def test_empty_query_safe():
    detect = _load_helper()
    methods, is_enum = detect("")
    assert methods == []
    assert is_enum is False
    methods, is_enum = detect(None)
    assert methods == []
    assert is_enum is False
