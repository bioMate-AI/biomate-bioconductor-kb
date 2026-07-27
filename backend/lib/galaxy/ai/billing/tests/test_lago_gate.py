"""Lago is dropped from the critical path (flat-tier billing). BILLING_LAGO_ENABLED
defaults off: emits no-op and quota reads return None (→ DEFAULT_PLAN_LIMITS)."""
import os
import pytest
from galaxy.ai.billing.core.lago_client import lago_enabled, LagoClient, LagoEvent


def test_lago_disabled_by_default(monkeypatch):
    monkeypatch.delenv("BILLING_LAGO_ENABLED", raising=False)
    assert lago_enabled() is False


def test_lago_enabled_when_explicitly_set(monkeypatch):
    monkeypatch.setenv("BILLING_LAGO_ENABLED", "true")
    assert lago_enabled() is True
    monkeypatch.setenv("BILLING_LAGO_ENABLED", "false")
    assert lago_enabled() is False


def test_send_event_noops_when_disabled(monkeypatch):
    monkeypatch.delenv("BILLING_LAGO_ENABLED", raising=False)
    c = LagoClient(api_key="dummy")
    evt = LagoEvent(
        transaction_id="t1", external_subscription_id="bm_x_base",
        code="llm", timestamp=0, properties={"value": 1},
    )
    # Returns success without any HTTP call (would raise/connect if it tried).
    assert c.send_event(evt) is True
    assert c.send_batch_events([evt]) == 1


def test_quota_read_returns_none_when_disabled(monkeypatch):
    monkeypatch.delenv("BILLING_LAGO_ENABLED", raising=False)
    c = LagoClient(api_key="dummy")
    # None → quota_enforcer falls back to DEFAULT_PLAN_LIMITS.
    assert c.get_plan_limit_usd("premium") is None
    assert c.get_current_usage("u1") is None


def test_provisioning_noops_when_disabled(monkeypatch):
    monkeypatch.delenv("BILLING_LAGO_ENABLED", raising=False)
    c = LagoClient(api_key="dummy")
    assert c.upsert_customer("u1", "a@b.co", "A") is True
    assert c.assign_plan("u1", "premium") is True
