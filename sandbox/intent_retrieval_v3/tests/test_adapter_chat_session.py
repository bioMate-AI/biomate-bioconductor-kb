"""Tests for the chat session resume decision adapter."""
from __future__ import annotations

import pytest

from sandbox.intent_retrieval_v3.adapters.chat_session import (
    should_resume_chat_session,
)
from sandbox.intent_retrieval_v3.core.yaml_loader import reset_loader_cache


@pytest.fixture(autouse=True)
def _clear_cache():
    reset_loader_cache()


# ─── NEW intents always win ──────────────────────────────────────────────

def test_new_project_overrides_recent_session():
    """Even with a fresh terminal session, 'new project' fires NEW."""
    last = {"id": "abc123", "status": "completed", "age_minutes": 5}
    out = should_resume_chat_session("start a new project on protein design", last)
    assert out["decision"] == "new"
    assert out["session_id"] is None  # don't pass through the old id


def test_clear_context_overrides_resume():
    last = {"id": "x", "status": "completed", "age_minutes": 2}
    out = should_resume_chat_session("clear context and start over", last)
    assert out["decision"] == "new"


def test_new_overrides_explicit_resume_phrase():
    """If query contains BOTH 'continue' and 'new project', NEW wins."""
    last = {"id": "x", "status": "completed", "age_minutes": 5}
    out = should_resume_chat_session(
        "continue the old work, but actually start a new project instead", last
    )
    assert out["decision"] == "new"


# ─── RESUME intents fire when no NEW intent active ──────────────────────

def test_resume_intent_with_session_returns_resume():
    last = {"id": "abc", "status": "running", "age_minutes": 10}
    out = should_resume_chat_session("what's the status of my run?", last)
    assert out["decision"] == "resume"
    assert out["session_id"] == "abc"


def test_resume_intent_without_session_is_uncertain():
    """Library doesn't fabricate a session — needs a real last_session."""
    out = should_resume_chat_session("what's the status of my run?", None)
    assert out["decision"] == "uncertain"


def test_pick_up_where_we_left_off_resumes():
    last = {"id": "xyz", "status": "completed", "age_minutes": 15}
    out = should_resume_chat_session("pick up where we left off", last)
    assert out["decision"] == "resume"
    assert out["session_id"] == "xyz"


# ─── Default rule: recent terminal session ──────────────────────────────

def test_default_resume_for_recent_terminal():
    """No intent fires, but session is recent + terminal → default resume."""
    last = {"id": "s1", "status": "completed", "age_minutes": 5}
    out = should_resume_chat_session("show me what we got", last)
    # 'show me the results' is in resume YAML; let's pick something
    # genuinely neutral:
    out2 = should_resume_chat_session("hello there", last)
    assert out2["decision"] == "resume"
    assert out2["reason"].startswith("recent terminal session")


def test_no_default_resume_when_stale():
    """Old session shouldn't auto-resume."""
    last = {"id": "s1", "status": "completed", "age_minutes": 120}
    out = should_resume_chat_session("hello there", last)
    assert out["decision"] == "uncertain"


def test_no_default_resume_when_running():
    """Running session is mid-execution; require explicit resume intent."""
    last = {"id": "s1", "status": "running", "age_minutes": 5}
    out = should_resume_chat_session("hello there", last)
    assert out["decision"] == "uncertain"


# ─── Disqualifier handling ──────────────────────────────────────────────

def test_continue_with_new_disqualifier_does_not_resume():
    """'continue' is normally a resume trigger; 'new conversation' disqualifies."""
    last = {"id": "s1", "status": "completed", "age_minutes": 5}
    out = should_resume_chat_session(
        "continue to a new conversation about something else", last
    )
    # 'new conversation' is in new_project triggers AND in continue_previous's disqualifier
    # Result: new_project fires → decision='new'
    assert out["decision"] == "new"


def test_topic_pivot_with_related_disqualifier():
    """'moving on' fires topic_pivot, but 'the same' disqualifies."""
    last = {"id": "s1", "status": "completed", "age_minutes": 5}
    out = should_resume_chat_session(
        "moving on to the same dataset for another angle", last
    )
    # topic_pivot disqualified by 'the same' → falls through
    # No new-intent fires → default rule applies (recent terminal → resume)
    assert out["decision"] == "resume"


# ─── Edge cases ──────────────────────────────────────────────────────────

def test_empty_query_falls_back_to_metadata():
    last = {"id": "s1", "status": "completed", "age_minutes": 5}
    out = should_resume_chat_session("", last)
    assert out["decision"] == "resume"
    assert "metadata-only" in out["reason"]


def test_empty_query_no_session_is_uncertain():
    out = should_resume_chat_session("", None)
    assert out["decision"] == "uncertain"


def test_no_query_no_session():
    out = should_resume_chat_session("", {})
    assert out["decision"] == "uncertain"


def test_response_shape_invariants():
    """Every response has decision, reason, confidence, session_id."""
    for query in ("", "hello", "new project", "continue", "what's up"):
        out = should_resume_chat_session(query, {"id": "x", "status": "completed",
                                                   "age_minutes": 5})
        assert {"decision", "reason", "confidence", "session_id"} <= set(out.keys())
        assert out["decision"] in {"resume", "new", "uncertain"}
        assert 0.0 <= out["confidence"] <= 1.0
