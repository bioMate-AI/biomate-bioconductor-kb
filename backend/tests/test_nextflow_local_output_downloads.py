"""Regression coverage for local Nextflow output download links.

The output listing previously emitted its local file paths through an S3-only
endpoint, so every listed local output failed with HTTP 400 when opened.
"""
from __future__ import annotations

from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
EXECUTOR = (
    REPO_ROOT
    / "backend"
    / "lib"
    / "galaxy"
    / "webapps"
    / "galaxy"
    / "api"
    / "nextflow_executor.py"
)


def _local_download_sections() -> tuple[str, str]:
    source = EXECUTOR.read_text()
    handler_start = source.index("def download_s3_output(")
    listing_start = source.index("def list_run_output_files(")
    listing_end = source.index("@router.get(\"/api/qc/profiles\"", listing_start)
    return source[handler_start:listing_start], source[listing_start:listing_end]


def test_local_listing_uses_a_local_download_endpoint_not_the_s3_only_parameter():
    _, listing = _local_download_sections()
    assert "def _local_files(output_dir: Path)" in listing
    assert '"/api/nextflow/outputs/download?local_path="' in listing
    assert 'f"{quote(str(f))}&run_id={quote(run_id)}"' in listing
    # The historic broken local URL passed a filesystem path as `s3_uri`.
    assert 'f"/api/nextflow/outputs/download?s3_uri={str(f)}' not in listing


def test_local_download_keeps_the_run_output_root_as_the_authorization_boundary():
    handler, _ = _local_download_sections()
    assert "local_path: Optional[str] = None" in handler
    assert "requested.relative_to(output_root)" in handler
    assert "FileResponse(requested, filename=requested.name)" in handler
