"""
HTTP-level end-to-end tests for the customer feedback router.

Closes audit gap 3g — "no HTTP-level tests". Uses FastAPI TestClient against
the real router; mounts to a fresh app instance per test to avoid cross-test
state. JSONL files are redirected to a tmp dir so tests don't write to the
production training corpus.

Run:
    PYTHONPATH=backend/lib pytest backend/lib/galaxy/ai/drug_discovery/tests/
or:
    PYTHONPATH=backend/lib python -m \
        backend.lib.galaxy.ai.drug_discovery.tests.test_feedback_router
"""
from __future__ import annotations

import json
import os
import sys
import tempfile
from pathlib import Path
from unittest.mock import patch

# Allow running as a script
if __name__ == "__main__":
    sys.path.insert(0, str(Path(__file__).resolve().parents[5]))


def _make_client(tmp_dir: Path):
    """
    Build an isolated TestClient with JSONL paths redirected to tmp_dir and
    auth in dev-pass-through mode. Imported lazily so module import doesn't
    explode in environments missing fastapi/peft.
    """
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    from galaxy.ai.drug_discovery import feedback_io
    # Redirect all JSONL targets to the tmp dir
    feedback_io.CUSTOMER_PAIRS   = tmp_dir / "customer_pairs.jsonl"
    feedback_io.CHECKER_FEEDBACK = tmp_dir / "checker_feedback.jsonl"
    feedback_io.CITATION_EXTS    = tmp_dir / "citation_extensions.jsonl"
    feedback_io.PROMPT_TUNING    = tmp_dir / "prompt_tuning.jsonl"

    from galaxy.ai.drug_discovery.feedback_router import router
    app = FastAPI()
    app.include_router(router)
    return TestClient(app)


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

def test_edit_endpoint_records_pair(tmp_path: Path):
    client = _make_client(tmp_path)
    resp = client.post(
        "/api/ind-report/projects/proj-1/edit",
        json={
            "paragraph_id": "2.6.6.2-p3",
            "original":  "The NOAEL was approximately 100 mg/kg in rats.",
            "edited":    "The NOAEL of 100 mg/kg/day was established in the rat.",
            "section_type": "tox_overview",
            "structured_input": "Write §2.6.6.2 repeat-dose summary",
        },
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["recorded"] is True
    assert "id" in body
    rows = (tmp_path / "customer_pairs.jsonl").read_text().strip().splitlines()
    assert len(rows) == 1
    row = json.loads(rows[0])
    assert row["meta"]["paragraph_id"] == "2.6.6.2-p3"


def test_edit_endpoint_rejects_empty(tmp_path: Path):
    client = _make_client(tmp_path)
    resp = client.post(
        "/api/ind-report/projects/proj-1/edit",
        json={
            "paragraph_id": "p1", "original": "abc", "edited": "   ",
            "section_type": "tox_overview",
        },
    )
    assert resp.status_code == 400


def test_edit_endpoint_no_op_when_unchanged(tmp_path: Path):
    client = _make_client(tmp_path)
    resp = client.post(
        "/api/ind-report/projects/proj-1/edit",
        json={
            "paragraph_id": "p1",
            "original": "Identical paragraph text.",
            "edited":   "Identical paragraph text.",
            "section_type": "tox_overview",
        },
    )
    assert resp.status_code == 200
    assert resp.json()["recorded"] is False
    assert not (tmp_path / "customer_pairs.jsonl").exists() \
        or (tmp_path / "customer_pairs.jsonl").read_text() == ""


def test_dismiss_endpoint_records_reason(tmp_path: Path):
    client = _make_client(tmp_path)
    resp = client.post(
        "/api/ind-report/audit/finding-42/dismiss",
        json={
            "rule_id": "hERG_required",
            "section_type": "tox_overview",
            "reason": "not_applicable",
            "free_text": "Topical product, no systemic exposure.",
        },
    )
    assert resp.status_code == 200, resp.text
    rows = (tmp_path / "checker_feedback.jsonl").read_text().strip().splitlines()
    assert len(rows) == 1
    row = json.loads(rows[0])
    assert row["dismissed_reason"] == "not_applicable"
    assert row["rule_id"] == "hERG_required"


def test_dismiss_endpoint_rejects_unknown_reason(tmp_path: Path):
    client = _make_client(tmp_path)
    resp = client.post(
        "/api/ind-report/audit/finding-42/dismiss",
        json={
            "rule_id": "hERG_required",
            "section_type": "tox_overview",
            "reason": "i_disagree_lol",  # not in the allowed regex
        },
    )
    assert resp.status_code == 422  # pydantic validation error


def test_citation_suggest_records(tmp_path: Path):
    client = _make_client(tmp_path)
    resp = client.post(
        "/api/ind-report/citations/suggest",
        json={
            "guideline_id": "CDE 化学药物非临床研究技术指导原则",
            "rationale": "Required for NMPA submission",
            "document_only": False,
        },
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["queued_for_review"] is True
    rows = (tmp_path / "citation_extensions.jsonl").read_text().strip().splitlines()
    assert len(rows) == 1


def test_citation_suggest_rejects_empty_id(tmp_path: Path):
    client = _make_client(tmp_path)
    resp = client.post(
        "/api/ind-report/citations/suggest",
        json={"guideline_id": "  ", "rationale": "x"},
    )
    assert resp.status_code == 400


def test_regenerate_records_instruction(tmp_path: Path):
    client = _make_client(tmp_path)
    resp = client.post(
        "/api/ind-report/sections/2.6.6.3/regenerate",
        json={
            "instruction": "Use more conservative language about the Ames equivocal finding",
            "before": "The Ames assay was equivocal.",
            "after":  "The Ames assay returned an equivocal result that warrants further investigation.",
        },
    )
    assert resp.status_code == 200, resp.text
    rows = (tmp_path / "prompt_tuning.jsonl").read_text().strip().splitlines()
    assert len(rows) == 1
    row = json.loads(rows[0])
    assert "conservative" in row["instruction"]


def test_regenerate_no_instruction_is_no_op(tmp_path: Path):
    client = _make_client(tmp_path)
    resp = client.post(
        "/api/ind-report/sections/2.6.6.3/regenerate",
        json={"instruction": "  "},
    )
    assert resp.status_code == 200
    assert resp.json()["recorded"] is False


def test_internal_queue_fails_closed_without_env(tmp_path: Path):
    # No BIOMATE_INTERNAL_KEY → 503
    with patch.dict(os.environ, {}, clear=False):
        os.environ.pop("BIOMATE_INTERNAL_KEY", None)
        client = _make_client(tmp_path)
        resp = client.get("/api/regulatory/feedback/queue?kind=customer_pairs")
    assert resp.status_code == 503


def test_internal_queue_with_correct_key(tmp_path: Path):
    with patch.dict(os.environ, {"BIOMATE_INTERNAL_KEY": "test-key-123"}):
        client = _make_client(tmp_path)
        # write a row directly so the queue has content
        from galaxy.ai.drug_discovery.feedback_io import append_jsonl
        append_jsonl(tmp_path / "customer_pairs.jsonl",
                     {"prompt": "x", "chosen": "y", "rejected": "z"})
        resp = client.get(
            "/api/regulatory/feedback/queue?kind=customer_pairs",
            headers={"Authorization": "Bearer test-key-123"},
        )
        assert resp.status_code == 200
        body = resp.json()
        assert body["kind"] == "customer_pairs"
        assert len(body["items"]) >= 1


def test_active_adapter_default_public(tmp_path: Path):
    client = _make_client(tmp_path)
    resp = client.get("/api/regulatory/active_adapter")
    assert resp.status_code == 200
    body = resp.json()
    assert "adapter_name" in body
    assert body["entitled"] is False  # no paid_orgs.json → not entitled


def test_active_adapter_unentitled_org_falls_back(tmp_path: Path):
    client = _make_client(tmp_path)
    resp = client.get(
        "/api/regulatory/active_adapter",
        headers={"X-BioMate-Org-Id": "random-org-not-paid"},
    )
    body = resp.json()
    assert body["entitled"] is False
    assert body["customized_for"] is None


def test_rate_limit_eventually_429s(tmp_path: Path):
    # Push 65 requests (default 60 rpm) and expect at least one 429
    client = _make_client(tmp_path)
    statuses = []
    for i in range(65):
        r = client.post(
            "/api/ind-report/projects/proj-rl/edit",
            json={
                "paragraph_id": f"p{i}", "original": "a", "edited": f"b{i}",
                "section_type": "tox_overview",
            },
        )
        statuses.append(r.status_code)
        if r.status_code == 429:
            break
    assert 429 in statuses, f"no 429 seen in {len(statuses)} requests"


if __name__ == "__main__":
    # Lightweight runner when pytest isn't available
    import inspect
    tests = [
        (name, obj) for name, obj in globals().items()
        if name.startswith("test_") and callable(obj)
    ]
    passed = failed = 0
    for name, fn in tests:
        with tempfile.TemporaryDirectory() as td:
            try:
                fn(Path(td))
                print(f"  ✓ {name}")
                passed += 1
            except AssertionError as e:
                print(f"  ✗ {name}: {e}")
                failed += 1
            except Exception as e:
                print(f"  ✗ {name}: {type(e).__name__}: {e}")
                failed += 1
    print(f"\n{passed} passed, {failed} failed")
    sys.exit(0 if failed == 0 else 1)
