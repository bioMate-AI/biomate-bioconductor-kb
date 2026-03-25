"""
Unit tests for the LLM-based multi-task query classifier.

These tests exercise _looks_like_multi_task, _classify_multi_task_llm, and the
module-level cache without requiring a real LLM API key. _call_llm_fast is
mocked so tests run offline and instantaneously.
"""
import sys
import os
import pytest
from unittest.mock import MagicMock, patch

# ---------------------------------------------------------------------------
# Path setup so tests can be run from the repo root:
#   python -m pytest backend/lib/galaxy/ai/tests/test_multi_task_classifier.py
# ---------------------------------------------------------------------------
_BACKEND_LIB = os.path.join(os.path.dirname(__file__), "..", "..", "..", "..")
if _BACKEND_LIB not in sys.path:
    sys.path.insert(0, _BACKEND_LIB)


def _make_assistant(llm_response: str):
    """
    Build a minimal AIAssistant-like object with:
    - _call_llm_fast mocked to return *llm_response*
    - _looks_like_multi_task and _classify_multi_task_llm bound from the real class
    """
    # Import lazily so the test module doesn't crash if Galaxy isn't importable
    # at collection time — the skip logic handles that gracefully.
    from galaxy.ai.ai_assistant import AIAssistant

    assistant = MagicMock(spec=AIAssistant)
    assistant._call_llm_fast = MagicMock(return_value=llm_response)

    # Bind the real methods onto the mock instance
    assistant._looks_like_multi_task = AIAssistant._looks_like_multi_task.__get__(assistant)
    assistant._classify_multi_task_llm = AIAssistant._classify_multi_task_llm.__get__(assistant)
    return assistant


def _clear_cache():
    """Clear the module-level classification cache between tests."""
    import galaxy.ai.ai_assistant as mod
    mod._MULTI_TASK_CACHE.clear()


# ---------------------------------------------------------------------------
# Parametrised happy-path tests
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("query,llm_json,expected_multi,expected_count", [
    (
        "Run FastQC on my samples",
        '{"is_multi_task": false, "task_count": 1, "reason": "Single QC step requested"}',
        False, 1,
    ),
    (
        "First run QC, then align to hg38, then call variants",
        '{"is_multi_task": true, "task_count": 3, "reason": "Three distinct analysis steps chained"}',
        True, 3,
    ),
    (
        "Analyze my RNA-seq data with differential expression",
        '{"is_multi_task": false, "task_count": 1, "reason": "Single analysis request even though complex"}',
        False, 1,
    ),
    (
        "Run QC and then do differential expression analysis",
        '{"is_multi_task": true, "task_count": 2, "reason": "QC followed by DE analysis"}',
        True, 2,
    ),
    (
        "What is the best tool for short-read alignment?",
        '{"is_multi_task": false, "task_count": 1, "reason": "Informational query, not a workflow"}',
        False, 1,
    ),
])
def test_classification_from_llm_response(query, llm_json, expected_multi, expected_count):
    _clear_cache()
    assistant = _make_assistant(llm_json)
    result = assistant._looks_like_multi_task(query)
    assert result == expected_multi, f"Expected is_multi_task={expected_multi} for: {query!r}"


# ---------------------------------------------------------------------------
# Regression: false positives the old keyword heuristic would have triggered
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("query,description", [
    ("Find and annotate SNPs in my VCF",
     "'and' present but single conceptual task"),
    ("What tools are first choice for assembly?",
     "'first' present but not a chained workflow"),
    ("Run alignment and export the BAM file",
     "'and' present but a single pipeline step with output"),
    ("Compare STAR and HISAT2 for RNA-seq alignment",
     "compound noun with 'and', not a chained execution"),
])
def test_old_heuristic_false_positives_now_classified_correctly(query, description):
    """
    The old heuristic fired on any occurrence of 'and'/'first'/'then'.
    The LLM classifier correctly returns False for these single-intent queries.
    """
    _clear_cache()
    # All these should be classified as single-task
    llm_json = '{"is_multi_task": false, "task_count": 1, "reason": "Single-intent query"}'
    assistant = _make_assistant(llm_json)
    result = assistant._looks_like_multi_task(query)
    assert result is False, f"False positive for ({description}): {query!r}"


# ---------------------------------------------------------------------------
# Fallback behaviour on LLM failure
# ---------------------------------------------------------------------------

def test_llm_failure_defaults_to_single_task():
    """If _call_llm_fast raises, _looks_like_multi_task must return False (safe path)."""
    from galaxy.ai.ai_assistant import AIAssistant

    assistant = MagicMock(spec=AIAssistant)
    assistant._call_llm_fast = MagicMock(side_effect=RuntimeError("API unreachable"))
    assistant._looks_like_multi_task = AIAssistant._looks_like_multi_task.__get__(assistant)
    assistant._classify_multi_task_llm = AIAssistant._classify_multi_task_llm.__get__(assistant)

    _clear_cache()
    result = assistant._looks_like_multi_task("Run QC then DE analysis")
    assert result is False


def test_invalid_json_defaults_to_single_task():
    """If the LLM returns non-JSON, the fallback must kick in and return False."""
    from galaxy.ai.ai_assistant import AIAssistant

    assistant = MagicMock(spec=AIAssistant)
    assistant._call_llm_fast = MagicMock(return_value="Sorry, I cannot classify that.")
    assistant._looks_like_multi_task = AIAssistant._looks_like_multi_task.__get__(assistant)
    assistant._classify_multi_task_llm = AIAssistant._classify_multi_task_llm.__get__(assistant)

    _clear_cache()
    result = assistant._looks_like_multi_task("Run QC then DE analysis")
    assert result is False


# ---------------------------------------------------------------------------
# Caching behaviour
# ---------------------------------------------------------------------------

def test_cache_prevents_second_llm_call():
    """The same query must not trigger a second LLM call."""
    _clear_cache()
    llm_json = '{"is_multi_task": true, "task_count": 2, "reason": "Two steps"}'
    assistant = _make_assistant(llm_json)

    query = "Run QC then align reads"
    assistant._looks_like_multi_task(query)   # first call — hits LLM
    assistant._looks_like_multi_task(query)   # second call — should hit cache

    assert assistant._call_llm_fast.call_count == 1, (
        "LLM was called more than once for the same query — cache is not working"
    )


def test_cache_is_case_and_whitespace_insensitive():
    """Queries that differ only by case/leading whitespace must share a cache entry."""
    _clear_cache()
    llm_json = '{"is_multi_task": false, "task_count": 1, "reason": "Same query"}'
    assistant = _make_assistant(llm_json)

    assistant._looks_like_multi_task("Run FastQC")
    assistant._looks_like_multi_task("  run fastqc  ")   # normalised to same key

    assert assistant._call_llm_fast.call_count == 1


def test_cache_evicts_oldest_when_full():
    """When the cache exceeds _MULTI_TASK_CACHE_MAX entries, the oldest is evicted."""
    import galaxy.ai.ai_assistant as mod
    _clear_cache()

    llm_json = '{"is_multi_task": false, "task_count": 1, "reason": "test"}'

    # Fill the cache to capacity using unique queries
    for i in range(mod._MULTI_TASK_CACHE_MAX):
        assistant = _make_assistant(llm_json)
        assistant._looks_like_multi_task(f"unique query number {i}")

    assert len(mod._MULTI_TASK_CACHE) == mod._MULTI_TASK_CACHE_MAX

    # One more entry should evict the oldest and keep the size constant
    assistant = _make_assistant(llm_json)
    assistant._looks_like_multi_task("the final overflow query")
    assert len(mod._MULTI_TASK_CACHE) == mod._MULTI_TASK_CACHE_MAX


# ---------------------------------------------------------------------------
# Markdown fence stripping in _classify_multi_task_llm
# ---------------------------------------------------------------------------

def test_markdown_fenced_json_is_parsed_correctly():
    """LLM responses wrapped in ```json ... ``` must still parse correctly."""
    _clear_cache()
    fenced_response = '```json\n{"is_multi_task": true, "task_count": 2, "reason": "Two steps"}\n```'
    assistant = _make_assistant(fenced_response)
    result = assistant._looks_like_multi_task("Run QC then alignment")
    assert result is True
