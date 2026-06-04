"""Path A — workflow → IND pipeline_data writer.

Implements `docs/20260603_IND_DATA_FLOW_PATH_A.md` items A.1 + A.5.

The IND module's Step 1-5 view reads from
`data/ind_demo/registry/pipeline_data/<project_id>.json`. Before Path A,
those sidecars were hand-curated demo data. After Path A, BioMate
workflows (ADMET / PBPK / lead opt) and customer uploads can write to
them. Each write:

  1. Loads the current sidecar (if any)
  2. Computes the new block (admet / pbpk / leads / compounds) from the
     workflow output payload
  3. Applies the precedence rule: an uploaded measured block (PDF/CSV
     from A1) overrides a computed workflow block unless force=True
  4. Atomically writes the updated sidecar
  5. Appends a row to `pipeline_data_audit.jsonl` for the audit chain
  6. Fans out an SSE event to any subscriber listening on the project's
     /events channel

The SSE bus is in-memory; for multi-worker gunicorn deploys this is a
TODO for Redis pub-sub.
"""
from __future__ import annotations

import asyncio
import json
import logging
import time
from collections import defaultdict
from pathlib import Path
from typing import Any, Optional

log = logging.getLogger(__name__)

_REPO_ROOT = Path(__file__).resolve().parents[5]
_PIPELINE_DATA_DIR = _REPO_ROOT / "data" / "ind_demo" / "registry" / "pipeline_data"
_AUDIT_LOG = _REPO_ROOT / "data" / "ind_demo" / "registry" / "pipeline_data_audit.jsonl"

VALID_STEPS = ("admet", "pbpk", "leads", "compounds")
VALID_SOURCES = ("workflow", "upload", "manual_rerun", "chat_roll_in", "auto_hook", "manual")


# ---------------------------------------------------------------------------
# SSE bus (in-memory, single-worker dev)
# ---------------------------------------------------------------------------
#
# TODO(redis): when the prod gunicorn picks up multi-worker, swap this for
# `redis.asyncio.Redis.pubsub()`. The fan-out shape stays identical.

_subscribers: dict[str, set[asyncio.Queue]] = defaultdict(set)


def subscribe(project_id: str) -> asyncio.Queue:
    q: asyncio.Queue = asyncio.Queue(maxsize=64)
    _subscribers[project_id].add(q)
    return q


def unsubscribe(project_id: str, q: asyncio.Queue) -> None:
    _subscribers.get(project_id, set()).discard(q)


def _fanout(project_id: str, event: str, data: dict) -> None:
    """Push the event to every queue subscribed to this project.

    Best-effort; queues that have backpressure get a stale message dropped
    instead of blocking the writer.
    """
    payload = {"event": event, "data": data}
    for q in list(_subscribers.get(project_id, set())):
        try:
            q.put_nowait(payload)
        except asyncio.QueueFull:
            # Drop the oldest message to make room.
            try:
                q.get_nowait()
                q.put_nowait(payload)
            except Exception:
                pass


# ---------------------------------------------------------------------------
# Sidecar read/write
# ---------------------------------------------------------------------------

def _sidecar_path(project_id: str) -> Path:
    return _PIPELINE_DATA_DIR / f"{project_id}.json"


def _load_sidecar(project_id: str) -> dict:
    path = _sidecar_path(project_id)
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text())
    except Exception as exc:
        log.warning("[pipeline_writer] failed to read %s: %s", path, exc)
        return {}


def _save_sidecar(project_id: str, data: dict) -> None:
    path = _sidecar_path(project_id)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(data, indent=2))
    tmp.replace(path)


def _append_audit(record: dict) -> None:
    _AUDIT_LOG.parent.mkdir(parents=True, exist_ok=True)
    with _AUDIT_LOG.open("a") as f:
        f.write(json.dumps(record) + "\n")


# ---------------------------------------------------------------------------
# Precedence rule (D.3 from the design doc)
# ---------------------------------------------------------------------------

def _is_protected_upload(block: Optional[dict]) -> bool:
    """A block with _provenance.source='upload' is the customer's measured
    data. Workflow auto-feed must NOT silently overwrite it."""
    if not block:
        return False
    prov = block.get("_provenance") or {}
    return prov.get("source") == "upload"


# ---------------------------------------------------------------------------
# Block writers
# ---------------------------------------------------------------------------

def _summarize_admet(block: dict) -> dict:
    return block.get("summary") or {}


def _summarize_pbpk(block: dict) -> dict:
    return {
        "status": block.get("status"),
        "cmaxWithin2": (block.get("metrics") or {}).get("cmaxWithin2"),
        "aucWithin2": (block.get("metrics") or {}).get("aucWithin2"),
    }


def _summarize_leads(block: dict) -> dict:
    ranking = block.get("ranking") or []
    return {
        "evaluated": block.get("evaluated"),
        "top": ranking[0].get("id") if ranking else None,
    }


def _summarize_compounds(block: Any) -> dict:
    if isinstance(block, list):
        return {"count": len(block)}
    return {"len": len(str(block))}


_SUMMARIZERS = {
    "admet": _summarize_admet,
    "pbpk": _summarize_pbpk,
    "leads": _summarize_leads,
    "compounds": _summarize_compounds,
}


def _stamp_provenance(block: dict, source: str, workflow_run_id: str | None) -> dict:
    """Attach the _provenance field. Mutates `block` in place and returns it."""
    if not isinstance(block, dict):
        return block
    block["_provenance"] = {
        "source": source,
        "attached_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "workflow_run_id": workflow_run_id,
    }
    return block


def write_block(
    project_id: str,
    step: str,
    payload: Any,
    source: str,
    workflow_run_id: str | None = None,
    actor: str | None = None,
    force: bool = False,
) -> dict:
    """Generic per-step write.

    Args:
      project_id: which IND project
      step: one of VALID_STEPS — admet / pbpk / leads / compounds
      payload: the new block content (shape depends on step; mirror the
               TS types AdmetData / PbpkData / LeadsData / list[CompoundEntry])
      source: where the data came from (VALID_SOURCES)
      workflow_run_id: optional run id for the audit chain
      actor: optional user/system id for the audit chain
      force: if True, override the upload-precedence guard

    Returns:
      {ok, step, prev_summary, new_summary, blocked?}

    Side effects: updates the sidecar, appends to audit, fans out SSE.
    """
    if step not in VALID_STEPS:
        raise ValueError(f"invalid step: {step!r}")
    if source not in VALID_SOURCES:
        raise ValueError(f"invalid source: {source!r}")

    sidecar = _load_sidecar(project_id)
    prev_block = sidecar.get(step)

    # Precedence: a measured upload wins over a computed workflow write.
    if (
        not force
        and _is_protected_upload(prev_block)
        and source in ("workflow", "auto_hook", "chat_roll_in")
    ):
        log.info(
            "[pipeline_writer] blocked %s write to %s/%s — existing _provenance.source=upload (use force=True to override)",
            source, project_id, step,
        )
        return {
            "ok": False,
            "step": step,
            "blocked": True,
            "reason": "measured_upload_wins",
            "prev_summary": (_SUMMARIZERS.get(step, lambda b: {}))(prev_block or {}),
            "new_summary": None,
        }

    # Stamp provenance.
    new_block = payload
    if isinstance(new_block, dict):
        new_block = _stamp_provenance(dict(new_block), source, workflow_run_id)

    sidecar[step] = new_block
    if step == "compounds" and isinstance(new_block, list) and new_block:
        # Lift the lead SMILES so Step1 renders it.
        for c in new_block:
            if c.get("lead"):
                sidecar["lead_smiles"] = c.get("smiles")
                break
    _save_sidecar(project_id, sidecar)

    summarize = _SUMMARIZERS.get(step, lambda b: {})
    record = {
        "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "project_id": project_id,
        "step": step,
        "source": source,
        "workflow_run_id": workflow_run_id,
        "actor": actor,
        "prev_summary": summarize(prev_block or {}),
        "new_summary": summarize(new_block if isinstance(new_block, dict) else {}),
    }
    _append_audit(record)
    _fanout(project_id, "pipeline_data:updated", {
        "project_id": project_id,
        "step": step,
        "source": source,
        "workflow_run_id": workflow_run_id,
    })
    return {
        "ok": True,
        "step": step,
        "prev_summary": record["prev_summary"],
        "new_summary": record["new_summary"],
    }


# Step-specific aliases — mostly for clarity at the call site.
def write_admet_block(project_id: str, payload: dict, **kw) -> dict:
    return write_block(project_id, "admet", payload, **kw)


def write_pbpk_block(project_id: str, payload: dict, **kw) -> dict:
    return write_block(project_id, "pbpk", payload, **kw)


def write_leads_block(project_id: str, payload: dict, **kw) -> dict:
    return write_block(project_id, "leads", payload, **kw)


def write_compounds_block(project_id: str, payload: list, **kw) -> dict:
    return write_block(project_id, "compounds", payload, **kw)


# ---------------------------------------------------------------------------
# TODO(real S3 reads): when a workflow finishes, its outputs live at S3
# paths the executor knows. The chat affordance / auto-hook should call
# write_block(payload=...) with the structured TS-typed dict that the
# adapter built from the S3 CSV / parquet / json. That adapter is the
# next iteration:
#
#   from .workflow_output_adapter import parse_admet_outputs
#   payload = parse_admet_outputs(s3_paths={"admet_csv": "s3://..."})
#   write_admet_block(project_id, payload, source="workflow",
#                     workflow_run_id="af3-run-9182")
#
# For now the API accepts an already-structured payload from the chat
# affordance, which is the same flow Path B (manual upload) already
# uses for CSV → AdmetData extraction.
# ---------------------------------------------------------------------------
