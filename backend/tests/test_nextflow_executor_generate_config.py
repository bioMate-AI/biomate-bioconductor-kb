"""Regression guard: _generate_executor_config must not reference `request.*`.

The function `_generate_executor_config(compute, config_dir, *, user_id, run_id,
credentials, nf_path, output_location)` has no `request` parameter — it takes
specific kwargs only. Past incident (commit 930aab12c1b, 2026-06-19) introduced
`request.output_location` inside the function body, causing NameError on every
workflow dispatch (broke all /api/workflows/execute calls across every domain —
Bioc, pharma, drug discovery — for ~24 hours before user-reported).

Fixed 2026-06-20 by threading `output_location` as a kwarg from the caller.
This test prevents the class of bug from recurring:

1. STATIC: grep the function body — assert no `request.` reference inside
2. RUNTIME: call _generate_executor_config with all kwargs + a stub compute
   and assert no NameError + a valid Path or None is returned
"""
from __future__ import annotations

import re
import tempfile
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
EXECUTOR = REPO_ROOT / "backend" / "lib" / "galaxy" / "webapps" / "galaxy" / "api" / "nextflow_executor.py"


def _extract_function_body(text: str, fn_name: str) -> str:
    """Extract the body of a top-level def by indentation, until the next def."""
    lines = text.splitlines()
    start = None
    for i, line in enumerate(lines):
        if re.match(rf"^def\s+{re.escape(fn_name)}\s*\(", line):
            start = i
            break
    if start is None:
        raise AssertionError(f"function {fn_name} not found in {EXECUTOR}")
    end = len(lines)
    for j in range(start + 1, len(lines)):
        if re.match(r"^def\s+\w+\s*\(", lines[j]) or re.match(r"^class\s+\w+", lines[j]):
            end = j
            break
    return "\n".join(lines[start:end])


def test_generate_executor_config_no_request_reference():
    """Static guard — the function body must not reference `request.*`.

    The function signature doesn't include `request`. Any `request.foo` access
    inside the body is a NameError at runtime. Catches the 2026-06-19 regression
    (commit 930aab12c) without needing to import or boot the Galaxy app.
    """
    assert EXECUTOR.exists(), f"executor file not found at {EXECUTOR}"
    text = EXECUTOR.read_text()
    body = _extract_function_body(text, "_generate_executor_config")
    # Strip comments to avoid false positives if a comment legitimately mentions `request.`
    body_no_comments = re.sub(r"#.*", "", body)
    matches = re.findall(r"\brequest\.\w+", body_no_comments)
    assert not matches, (
        f"_generate_executor_config references `request.*` ({matches}) but its "
        f"signature has no `request` parameter — this is a NameError-at-dispatch "
        f"bug. Fixed in 2026-06-20 by threading output_location as a kwarg. "
        f"Don't reintroduce."
    )


def test_generate_executor_config_signature_has_output_location():
    """Static guard — output_location must be a kwarg of _generate_executor_config.

    Required so the caller in handle_execute can thread request.output_location
    through without reintroducing the `request.*` reference inside the function.
    """
    text = EXECUTOR.read_text()
    body = _extract_function_body(text, "_generate_executor_config")
    # First few lines hold the signature (def ... :)
    sig_block = body.split("\n)", 1)[0] if "\n)" in body else body.split("):", 1)[0]
    assert "output_location" in sig_block, (
        "_generate_executor_config must accept `output_location` as a kwarg so "
        "the caller can pass request.output_location through. Without it, the "
        "Phase C output-location picker is silently ignored. "
        "Restore the kwarg if removed."
    )


def test_generate_executor_config_runtime_no_name_error():
    """Runtime guard — actually invoke _generate_executor_config and verify it
    returns without NameError. Skips gracefully if the module can't be imported
    in the test sandbox (Galaxy boot can be heavy)."""
    try:
        import sys
        sys.path.insert(0, str(REPO_ROOT / "backend" / "lib"))
        from galaxy.webapps.galaxy.api import nextflow_executor as ne  # noqa: E402
    except Exception as e:
        pytest.skip(f"nextflow_executor not importable in this sandbox: {type(e).__name__}: {e}")

    with tempfile.TemporaryDirectory() as tmp:
        config_dir = Path(tmp)
        # Minimal compute dict that exercises the non-local path (which is
        # where the `outdir = ...` config-write happens — that's the line
        # that previously NameError'd on request.output_location).
        compute = {
            "executor": "awsbatch",
            "queue": "biomate-test-queue",
            "region": "us-west-2",
            "workDir": "s3://biomate-nextflow-work/test",
        }
        # output_location set to None → falls through _resolve_outdir's
        # "not output_location" branch → uses default bucket path.
        try:
            result = ne._generate_executor_config(
                compute,
                config_dir,
                user_id="testuser",
                run_id="testrun-001",
                credentials={},
                nf_path="/tmp/some.nf",
                output_location=None,
            )
        except NameError as e:
            pytest.fail(
                f"_generate_executor_config raised NameError — this is the "
                f"regression class we're guarding against: {e}"
            )
        # Either returns a Path (config file written) or None (local executor).
        # Both are acceptable; the point is no NameError.
        assert result is None or isinstance(result, Path)

        # Now exercise with output_location set — also must not NameError.
        try:
            result2 = ne._generate_executor_config(
                compute,
                config_dir,
                user_id="testuser",
                run_id="testrun-002",
                credentials={},
                nf_path="/tmp/some.nf",
                output_location={"type": "default"},
            )
        except NameError as e:
            pytest.fail(
                f"_generate_executor_config raised NameError when output_location "
                f"was set — the kwarg is not being used correctly: {e}"
            )
        assert result2 is None or isinstance(result2, Path)
