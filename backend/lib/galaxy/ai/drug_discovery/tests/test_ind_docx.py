"""Smoke tests for the DOCX export + S3 WORM mirror plumbing."""
from __future__ import annotations

import io
import os
from unittest.mock import patch

import pytest

from galaxy.ai.drug_discovery.ind_actions_router import (
    DocumentSection,
    _mirror_sign_row_to_s3_worm,
    _render_docx,
)


def test_render_docx_produces_valid_word_doc():
    project = {
        "molecule": "BMX-001",
        "sponsor": "BioMate AI",
        "target": "TYK2",
        "indication": "PsA",
        "regions": ["FDA"],
        "status": "in_progress",
    }
    sections = [
        DocumentSection(
            id="2.6.1",
            title="Pharmacology Written Summary",
            body="In the 28-day repeat-dose study, transient ALT elevation was "
            "observed in 4/10 males at 300 mg/kg/day.\n\nNOAEL = 100 mg/kg/day.",
        ),
        DocumentSection(id="2.6.2", title="Pharmacology Tabulated Summary", body=""),
    ]

    blob = _render_docx(project, sections)

    # ZIP magic — DOCX is a zip file
    assert blob[:2] == b"PK"
    assert len(blob) > 2000

    # Round-trip: open with python-docx and verify content landed
    from docx import Document
    parsed = Document(io.BytesIO(blob))
    text = "\n".join(p.text for p in parsed.paragraphs)
    assert "BMX-001" in text
    assert "BioMate AI" in text
    assert "§2.6.1" in text
    assert "transient ALT elevation was observed" in text
    assert "NO DATA AVAILABLE" in text  # empty §2.6.2 placeholder


def test_s3_worm_mirror_skipped_when_bucket_unset(monkeypatch):
    monkeypatch.delenv("BIOMATE_SIGN_AUDIT_S3_BUCKET", raising=False)
    # Should be a no-op, never touch boto3
    with patch("boto3.client") as mock_client:
        _mirror_sign_row_to_s3_worm("row-id", {
            "signed_at": "2026-05-29T10:00:00Z",
            "document_sha256": "a" * 64,
        })
        mock_client.assert_not_called()


def test_s3_worm_mirror_sets_object_lock(monkeypatch):
    monkeypatch.setenv("BIOMATE_SIGN_AUDIT_S3_BUCKET", "biomate-test-audit")
    monkeypatch.setenv("BIOMATE_SIGN_AUDIT_RETAIN_DAYS", "2555")

    # We have to re-import the module-level env vars because they're read
    # at import time. Easiest: monkeypatch the module constants directly.
    import galaxy.ai.drug_discovery.ind_actions_router as mod
    monkeypatch.setattr(mod, "_SIGN_AUDIT_S3_BUCKET", "biomate-test-audit")

    record = {
        "project_id": "demo",
        "user_id": "u1",
        "signed_at": "2026-05-29T10:00:00Z",
        "document_sha256": "b" * 64,
        "signer_title": "Director",
        "signer_creds": "PhD",
        "signature_scope": "§2.6",
        "adapter_versions": {},
    }

    with patch("boto3.client") as mock_client:
        mod._mirror_sign_row_to_s3_worm("sigid123", record)

    mock_client.assert_called_once()
    s3 = mock_client.return_value
    s3.put_object.assert_called_once()
    kwargs = s3.put_object.call_args.kwargs
    assert kwargs["Bucket"] == "biomate-test-audit"
    assert kwargs["ObjectLockMode"] == "COMPLIANCE"
    assert "ObjectLockRetainUntilDate" in kwargs
    assert "2026/05/29/sigid123.json" in kwargs["Key"]
    # Payload sha256 included in metadata for integrity audits
    assert "biomate-payload-sha256" in kwargs["Metadata"]


def test_s3_worm_mirror_swallows_exceptions(monkeypatch, caplog):
    """A failed mirror must NOT block the local sign — only log a warning."""
    import galaxy.ai.drug_discovery.ind_actions_router as mod
    monkeypatch.setattr(mod, "_SIGN_AUDIT_S3_BUCKET", "biomate-test-audit")

    record = {"signed_at": "2026-05-29T10:00:00Z", "document_sha256": "c" * 64}
    with patch("boto3.client", side_effect=RuntimeError("no AWS creds")):
        # Should not raise
        mod._mirror_sign_row_to_s3_worm("sig", record)
