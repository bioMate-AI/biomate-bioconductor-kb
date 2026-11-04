"""Regression tests for the three conflict resolutions made when merging integration/next-phase into the dev-lineage branch (PR #295).

billing_router : both sides edited the 'reuse an existing API key' query (branch: never reuse Galaxy's master key, newest first;
                 base: PostgreSQL-safe boolean `deleted`). The resolution must satisfy both.
llm_client     : both sides added an early route in generate_async (branch: local_only mode; base: on-prem direct providers).
nextflow_executor : QC-gate branch order (preprocessing path from the base side, generic S3 reconstruction from the branch) and
                 the local output listing (branch's download URL scheme + the rel_path/local_path fields the base-side frontend reads).
Source-text and AST based on purpose: the modules cannot be imported without the full Galaxy stack.
"""
from __future__ import annotations

import ast
import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2] / "backend" / "lib" / "galaxy"
BILLING = (ROOT / "ai" / "billing" / "api" / "billing_router.py").read_text()
LLM = (ROOT / "ai" / "llm_client.py").read_text()
EXEC = (ROOT / "webapps" / "galaxy" / "api" / "nextflow_executor.py").read_text()


def _helper():
    tree = ast.parse(BILLING)
    fn = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == "_existing_active_key_query")
    ns: dict = {}
    exec(compile(ast.Module([fn], []), "billing_helper", "exec"), ns)
    return ns["_existing_active_key_query"]


def _db():
    db = sqlite3.connect(":memory:")
    db.execute('CREATE TABLE api_keys (id INTEGER PRIMARY KEY, user_id INT, "key" TEXT, deleted BOOLEAN)')
    db.executemany('INSERT INTO api_keys (user_id, "key", deleted) VALUES (?,?,?)',
                   [(7, "old-active", 0), (7, "newer-active", 0), (7, "deleted-newer", 1), (7, "MASTER", 0), (8, "other-user", 0)])
    return db


def test_billing_query_skips_the_master_key_deleted_keys_and_returns_the_newest_active():
    sql, params = _helper()(7, "MASTER")
    assert params == {"uid": 7, "deleted": False, "mk": "MASTER"}      # boolean, not the integer 0
    assert _db().execute(sql, params).fetchone()[0] == "newer-active"


def test_billing_query_without_a_master_key_sends_no_null_parameter():
    sql, params = _helper()(7, None)
    assert "mk" not in params and ":mk" not in sql                   # no untyped NULL for server-side-binding drivers
    assert _db().execute(sql, params).fetchone()[0] == "MASTER"      # MASTER is the newest active row, returned when nothing is excluded


def test_billing_call_site_uses_the_helper_and_no_conflict_text_remains():
    assert "_existing_active_key_query(galaxy_user_id, _master_key)" in BILLING
    assert "deleted = 0" not in BILLING.split("def _existing_active_key_query")[1].split("@router.post")[0]
    for src in (BILLING, LLM, EXEC):
        assert "<<<<<<<" not in src and ">>>>>>>" not in src


def test_llm_generate_async_order_is_local_only_then_direct_providers_then_fallback_chain():
    body = LLM.split("async def generate_async(")[1].split("def call(")[0]
    i_local = body.index("if local_only():")
    i_direct = body.index("_DIRECT_PROVIDERS = {")
    i_chain = body.index("return await generate_with_fallback(")
    assert i_local < i_direct < i_chain
    assert "'openai_compatible', 'deepseek', 'zhipu', 'local'" in body


def test_qc_gate_branch_order_preprocessing_then_generic_then_cryo():
    body = EXEC.split("is_cryo = any(k in domain_upper", 1)[1]
    i_pre = body.index("# ── Preprocessing / cleaning QC path")
    i_generic = body.index("return _reconstruct_qc_from_s3(run_id, s3_output_files")
    i_cryo = body.index("# ── CryoEM path")
    assert i_pre < i_generic < i_cryo
    assert "is_preproc = any(k in domain_upper" in EXEC


def test_local_listing_keeps_the_branch_url_scheme_and_adds_the_fields_the_frontend_reads():
    listing = EXEC.split("def _local_files(output_dir: Path)")[1].split("return files")[0]
    assert '"/api/nextflow/outputs/download?local_path="' in listing
    assert '"rel_path": str(f.relative_to(output_dir))' in listing and '"local_path": str(f)' in listing
    assert "def _list_local_output_files(" in EXEC and "/api/nextflow/outputs/local-download" in EXEC   # base-side endpoint kept
