"""Tests for the LLMClient.call() shim.

The shim was added 2026-06-07 because 12 autofix callers used .call(...)
but LLMClient only defined .generate(prompt, **kw). DeepAnalysisAgent
crashed at the first LLM hop with AttributeError, silently making the
entire autofix3 chain inert despite the /status endpoint reporting
"operational".

These tests verify shape-normalization without hitting a real LLM:
generate() is mocked so we can assert the exact (prompt, kwargs) the
shim forwards.
"""

from __future__ import annotations

from unittest import mock

import pytest


def _make_client():
    """Build an LLMClient without invoking its real provider setup."""
    from galaxy.ai.llm_client import LLMClient
    c = LLMClient.__new__(LLMClient)  # bypass __init__
    c.generate = mock.MagicMock(return_value="LLM_RESPONSE")
    return c


def test_call_with_positional_prompt():
    c = _make_client()
    out = c.call("hello world", max_tokens=500)
    assert out == "LLM_RESPONSE"
    c.generate.assert_called_once_with("hello world", max_tokens=500)


def test_call_with_messages_list_kwarg():
    """The shape used by agent.py:415 and agent.py:649."""
    c = _make_client()
    out = c.call(
        messages=[{"role": "user", "content": "diagnose this OOM"}],
        provider="anthropic",
        temperature=0.1,
        max_tokens=1500,
    )
    assert out == "LLM_RESPONSE"
    # provider stripped; messages flattened; temperature/max_tokens preserved
    c.generate.assert_called_once_with(
        "diagnose this OOM", temperature=0.1, max_tokens=1500
    )


def test_call_with_messages_positional():
    """Some callers pass messages as the first positional arg."""
    c = _make_client()
    out = c.call(
        [{"role": "user", "content": "first"}, {"role": "assistant", "content": "ok"}],
        max_tokens=100,
    )
    assert out == "LLM_RESPONSE"
    # multi-turn messages: user content is bare, assistant gets a role tag
    expected_prompt = "first\n\n[assistant] ok"
    c.generate.assert_called_once_with(expected_prompt, max_tokens=100)


def test_call_drops_provider_kwarg():
    """`provider` is an autofix-side hint LLMClient doesn't accept."""
    c = _make_client()
    c.call("p", provider="anthropic", max_tokens=10)
    _, kwargs = c.generate.call_args
    assert "provider" not in kwargs


def test_call_empty_messages_yields_empty_prompt():
    c = _make_client()
    c.call(messages=[])
    c.generate.assert_called_once_with("", )


def test_call_missing_role_defaults_to_user():
    c = _make_client()
    c.call(messages=[{"content": "no role"}])
    c.generate.assert_called_once_with("no role", )


def test_call_with_prompt_kwarg():
    c = _make_client()
    c.call(prompt="explicit prompt", max_tokens=42)
    c.generate.assert_called_once_with("explicit prompt", max_tokens=42)


def test_autofix_callers_now_importable():
    """All autofix files that use .call() should import without AttributeError."""
    # This is a smoke check: importing the modules pulls in agent.py's
    # references to llm_client.call but doesn't actually invoke the LLM.
    from galaxy.ai.workflow_ops.autofix import agent  # noqa: F401
    from galaxy.ai.workflow_ops.autofix import agent_fixer  # noqa: F401
    from galaxy.ai.workflow_ops.autofix import llm_parameter_mapper  # noqa: F401
    from galaxy.ai.workflow_ops.autofix import parameter_mapper  # noqa: F401
    from galaxy.ai.workflow_ops.autofix.fixers import llm_first_fixer  # noqa: F401
    from galaxy.ai.workflow_ops.autofix.fixers import container_error_fixer  # noqa: F401
    from galaxy.ai.workflow_ops.autofix.fixers import llm_universal_fixer  # noqa: F401
    # LLMClient now exposes the .call attribute that all of them rely on
    from galaxy.ai.llm_client import LLMClient
    assert callable(getattr(LLMClient, "call", None))
