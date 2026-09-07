"""
Models + Inference API — data-centric upgrade.

Auto-discovered by Galaxy's include_all_package_routers() (any module in this
package exposing a module-level ``router`` is mounted).

This is a THIN presentation/dispatch layer over capability that already exists:

  - BioNeMo-covered models (structure / genomic / chemical evidence classes)
    are enumerated from ``galaxy.ai.bionemo_client._FUNCTIONS`` and dispatched
    through ``BioNeMoClient`` (self-host / NVCF NIM path).
  - Registered custom scoring models are enumerated + dispatched through
    ``galaxy.ai.drug_discovery.custom_model_registry.CustomModelRegistry`` +
    ``custom_model_wrapper`` (python / docker / rest wrappers).

It does NOT reinvent the registry, the wrappers, or the optimizer — it maps
their existing shapes onto the frontend contract below.

Contract (frontend is built against these EXACTLY):

  GET  /api/models
       -> [{id, name, family, version, origin, usedByCount}]

  GET  /api/models/{id}
       -> {identity, evidence, lineage, consumers, interface, versions}

  POST /api/models/{id}/infer   {inputs}
       -> {run_id}

  GET  /api/inference/{run_id}/result
       -> outputs shaped BY EVIDENCE CLASS (structure | genomic | chemical)

Honesty contract: if the BioNeMo NIM backend is unreachable (no NVIDIA_API_KEY
or a network/HTTP failure), inference returns a CLEARLY-LABELLED stub payload of
the correct SHAPE so the frontend can build against it. Stub payloads set
``stub: true`` and ``stub_reason`` at the top level and NEVER present fabricated
values as real measured science.
"""
# CRITICAL: keep this first. PEP 604 union syntax (``str | None``) below requires
# it on Python 3.9; without it gunicorn workers crash at boot (see
# nextflow_executor.py header for the incident history).
from __future__ import annotations

import logging
import threading
import time
import uuid
from typing import Any, Dict, List, Optional

from fastapi import HTTPException
from pydantic import BaseModel

from galaxy.webapps.galaxy.api import Router

log = logging.getLogger(__name__)

router = Router(tags=["models"])


# ─────────────────────────────────────────────────────────────────────────────
# Evidence classes
# ─────────────────────────────────────────────────────────────────────────────
# Every catalog model belongs to exactly one evidence class. The class drives
# BOTH how inference is dispatched and how the result is shaped.
STRUCTURE = "structure"
GENOMIC = "genomic"
CHEMICAL = "chemical"


# ─────────────────────────────────────────────────────────────────────────────
# BioNeMo catalog — enumerated from the existing bionemo_client function map.
# ─────────────────────────────────────────────────────────────────────────────
# We do NOT hardcode a parallel model list; we derive from _FUNCTIONS so the
# catalog stays in sync with the client. This table only adds presentation
# metadata (family, human name, evidence class, self-host origin) keyed by the
# client's function name.
_BIONEMO_META: Dict[str, Dict[str, Any]] = {
    # ── structure evidence class ──
    "boltz2": {
        "name": "Boltz-2",
        "family": "structure",
        "evidence_class": STRUCTURE,
        "version": "2.0",
        "interface": "rest",
    },
    "alphafold2": {
        "name": "AlphaFold2",
        "family": "structure",
        "evidence_class": STRUCTURE,
        "version": "2.3",
        "interface": "rest",
    },
    # NOTE: ESMFold was removed from the hosted catalogue (2026-09-14) — NVIDIA
    # deprecated the hosted ESMFold NVCF function (invocation 404s "not found for
    # account"). Boltz-2 / AlphaFold2 / OpenFold2 cover structure prediction via
    # hosted API. Re-add for a self-host deployment that runs an ESMFold NIM
    # (BIONEMO_SELF_HOST_PATH_ESMFOLD is still wired in bionemo_client.py).
    "openfold2": {
        "name": "OpenFold2",
        "family": "structure",
        "evidence_class": STRUCTURE,
        "version": "2.0",
        "interface": "rest",
    },
    # ── genomic evidence class ──
    "evo2_7b": {
        "name": "Evo2 7B",
        "family": "genomic",
        "evidence_class": GENOMIC,
        "version": "7b",
        "interface": "rest",
    },
    "evo2_40b": {
        "name": "Evo2 40B",
        "family": "genomic",
        "evidence_class": GENOMIC,
        "version": "40b",
        "interface": "rest",
    },
}

# BioNeMo model ids in the catalog are namespaced so they never collide with
# custom-model ids.
_BIONEMO_PREFIX = "bionemo:"
_CUSTOM_PREFIX = "custom:"


# ─────────────────────────────────────────────────────────────────────────────
# Custom-model catalog — enumerated from the CustomModelRegistry SQLite.
# ─────────────────────────────────────────────────────────────────────────────
# The registry is per-campaign. For the catalog we read the shared registration
# table directly (read-only) across all campaigns so the Models UI can list
# every registered custom model. Dispatch of a custom model still goes through
# the registry's in-process wrapper (a model must be re-registered in-process to
# actually run — the registry documents this).
def _campaign_db_dir() -> str:
    import os
    from pathlib import Path

    return os.environ.get(
        "BIOMATE_CAMPAIGN_DB_DIR",
        # backend/database/campaigns  (mirror of api_router._CAMPAIGN_DB_DIR)
        str(Path(__file__).resolve().parents[5] / "database" / "campaigns"),
    )


def _iter_custom_registrations() -> List[Dict[str, Any]]:
    """
    Read every custom_model_registration across all campaign DBs (read-only).

    Returns a flat list of dicts: {campaign_id, model_name, mode, weight,
    higher_is_better, enabled, registered_at}. Best-effort: a missing or
    corrupt campaign DB is skipped, not fatal.
    """
    import glob
    import os
    import sqlite3

    out: List[Dict[str, Any]] = []
    db_dir = _campaign_db_dir()
    for db_path in glob.glob(os.path.join(db_dir, "*.db")):
        try:
            with sqlite3.connect(f"file:{db_path}?mode=ro", uri=True) as conn:
                cur = conn.execute(
                    "SELECT name FROM sqlite_master "
                    "WHERE type='table' AND name='custom_model_registrations'"
                )
                if not cur.fetchone():
                    continue
                cur = conn.execute(
                    "SELECT campaign_id, model_name, mode, weight, "
                    "higher_is_better, enabled, registered_at "
                    "FROM custom_model_registrations"
                )
                cols = [d[0] for d in cur.description]
                for row in cur.fetchall():
                    out.append(dict(zip(cols, row)))
        except Exception as exc:  # noqa: BLE001 — best-effort catalog read
            log.debug("models: skip campaign DB %s: %s", db_path, exc)
    return out


def _custom_model_id(campaign_id: str, model_name: str) -> str:
    return f"{_CUSTOM_PREFIX}{campaign_id}/{model_name}"


def _parse_custom_id(model_id: str) -> Optional[tuple]:
    """(campaign_id, model_name) for a custom: id, else None."""
    if not model_id.startswith(_CUSTOM_PREFIX):
        return None
    rest = model_id[len(_CUSTOM_PREFIX):]
    if "/" not in rest:
        return None
    campaign_id, model_name = rest.split("/", 1)
    return campaign_id, model_name


# ─────────────────────────────────────────────────────────────────────────────
# Catalog assembly
# ─────────────────────────────────────────────────────────────────────────────
def _bionemo_catalog() -> List[Dict[str, Any]]:
    """Catalog rows for BioNeMo-covered models present in the client function map."""
    try:
        from galaxy.ai.bionemo_client import _FUNCTIONS
    except Exception as exc:  # noqa: BLE001
        log.warning("models: bionemo_client unavailable: %s", exc)
        return []

    rows: List[Dict[str, Any]] = []
    for fn_name, meta in _BIONEMO_META.items():
        if fn_name not in _FUNCTIONS:
            # Client dropped this function — don't advertise it.
            continue
        rows.append(
            {
                "id": f"{_BIONEMO_PREFIX}{fn_name}",
                "name": meta["name"],
                "family": meta["family"],
                "version": meta["version"],
                "origin": "self-host",  # BioNeMo NIM / self-host path
                "usedByCount": 0,
            }
        )
    return rows


def _custom_catalog() -> List[Dict[str, Any]]:
    """Catalog rows for registered custom models (usedByCount = campaigns using name)."""
    regs = _iter_custom_registrations()
    # usedByCount for a custom model name = number of campaigns that registered it.
    name_use: Dict[str, int] = {}
    for r in regs:
        name_use[r["model_name"]] = name_use.get(r["model_name"], 0) + 1

    rows: List[Dict[str, Any]] = []
    for r in regs:
        rows.append(
            {
                "id": _custom_model_id(r["campaign_id"], r["model_name"]),
                "name": r["model_name"],
                "family": r.get("mode", "custom"),  # python | docker | rest
                "version": "1",
                "origin": "custom",
                "usedByCount": name_use.get(r["model_name"], 0),
            }
        )
    return rows


def _catalog() -> List[Dict[str, Any]]:
    return _bionemo_catalog() + _custom_catalog()


def _find_catalog_row(model_id: str) -> Optional[Dict[str, Any]]:
    for row in _catalog():
        if row["id"] == model_id:
            return row
    return None


def _evidence_class_for(model_id: str) -> str:
    """Evidence class for a catalog id. Custom models are chemical (SMILES scorers)."""
    if model_id.startswith(_BIONEMO_PREFIX):
        fn_name = model_id[len(_BIONEMO_PREFIX):]
        meta = _BIONEMO_META.get(fn_name, {})
        return meta.get("evidence_class", STRUCTURE)
    # Custom scoring models score SMILES → chemical evidence class.
    return CHEMICAL


# ─────────────────────────────────────────────────────────────────────────────
# Inference run registry — cross-worker via the shared RunStateStore
# ─────────────────────────────────────────────────────────────────────────────
# Dev gunicorn runs --workers=4 with no sticky routing, so a module-level dict
# would 404 on ~75% of polls (POST lands on worker A, GET round-robins to B/C/D).
# We reuse the exact store the Nextflow executor uses (RUN_STATE_STORE=redis on
# dev). Our run_ids are uniquely prefixed ("inf-"), so they never collide with
# nextflow run keys; and because we never call set_pid(), the CompletionPoller
# skips them (it returns early when get_pid() is None) — no cross-contamination.
def _store():
    from galaxy.ai.runs.run_state_store import get_run_state_store

    return get_run_state_store()


def _new_run(model_id: str, evidence_class: str) -> str:
    run_id = f"inf-{uuid.uuid4().hex[:12]}"
    _store().set_run(
        run_id,
        {
            "run_id": run_id,
            "model_id": model_id,
            "evidence_class": evidence_class,
            "status": "running",
            "result": None,
            "error": None,
            "created_at": time.time(),
        },
    )
    return run_id


def _finish_run(run_id: str, result: Dict[str, Any]) -> None:
    _store().update_run(run_id, status="completed", result=result)


def _fail_run(run_id: str, error: str) -> None:
    _store().update_run(run_id, status="failed", error=error)


# ─────────────────────────────────────────────────────────────────────────────
# Response models (documentation / OpenAPI shape only — routes return dicts so
# stub/extra keys pass through unchanged).
# ─────────────────────────────────────────────────────────────────────────────
class ModelSummary(BaseModel):
    id: str
    name: str
    family: str
    version: str
    origin: str
    usedByCount: int


class InferRequest(BaseModel):
    inputs: Dict[str, Any] = {}


class InferResponse(BaseModel):
    run_id: str


# ``from __future__ import annotations`` turns the field annotations above into
# strings (forward refs). Resolve them at load time so the models validate under
# BOTH pydantic v1 (Galaxy runtime historically) and v2 (current), and under
# tools/tests that don't build the full FastAPI app.
class TogglePairRequest(BaseModel):
    """Optional explicit desired state for a learned-pair toggle; omitted → flip."""

    on: Optional[bool] = None


for _m in (ModelSummary, InferRequest, InferResponse, TogglePairRequest):
    # pydantic v2: model_rebuild() resolves from the module globals directly.
    _v2_rebuild = getattr(_m, "model_rebuild", None)
    if _v2_rebuild is not None:
        try:
            _v2_rebuild()
            continue
        except Exception as _exc:  # noqa: BLE001
            log.debug("models: v2 rebuild %s failed: %s", _m.__name__, _exc)
    # pydantic v1: update_forward_refs needs the referenced names in localns.
    _v1_rebuild = getattr(_m, "update_forward_refs", None)
    if _v1_rebuild is not None:
        try:
            _v1_rebuild(Any=Any, Dict=Dict, List=List, Optional=Optional)
        except Exception as _exc:  # noqa: BLE001
            log.debug("models: v1 rebuild %s failed: %s", _m.__name__, _exc)


# ─────────────────────────────────────────────────────────────────────────────
# GET /api/models
# ─────────────────────────────────────────────────────────────────────────────
@router.get(
    "/api/models",
    summary="List catalog models (BioNeMo self-host + registered custom).",
)
def list_models() -> List[Dict[str, Any]]:
    return _catalog()


# ─────────────────────────────────────────────────────────────────────────────
# GET /api/models/{id}
# ─────────────────────────────────────────────────────────────────────────────
@router.get(
    "/api/models/{model_id:path}",
    summary="Model detail: identity, evidence, lineage, consumers, interface, versions.",
)
def get_model(model_id: str) -> Dict[str, Any]:
    row = _find_catalog_row(model_id)
    if row is None:
        raise HTTPException(status_code=404, detail=f"Unknown model id: {model_id}")

    if model_id.startswith(_BIONEMO_PREFIX):
        fn_name = model_id[len(_BIONEMO_PREFIX):]
        meta = _BIONEMO_META.get(fn_name, {})
        interface_kind = meta.get("interface", "rest")
        # BioNeMo models have no per-instance measured eval gate in this layer —
        # we report the evidence structure with unmeasured verdict rather than a
        # fabricated number.
        evidence = {
            "gate": {"measured": None, "threshold": None, "verdict": "not_evaluated"},
            "calibration": None,
            "evalSetId": None,
        }
        lineage = {
            "datasetVersion": None,
            "trainingRunId": None,
            "priorVersions": [],
        }
        consumers: List[str] = []
        confidence_band = None
    else:
        parsed = _parse_custom_id(model_id)
        # parsed is guaranteed non-None because _find_catalog_row matched a custom id.
        campaign_id, model_name = parsed  # type: ignore[misc]
        interface_kind = _custom_interface_kind(row["family"])
        # Consumers = the campaigns that registered a model with this name.
        consumers = _custom_consumers(model_name)
        evidence = {
            "gate": {"measured": None, "threshold": None, "verdict": "not_evaluated"},
            "calibration": None,
            "evalSetId": None,
        }
        lineage = {
            "datasetVersion": None,
            "trainingRunId": campaign_id,  # the campaign that produced it
            "priorVersions": [],
        }
        confidence_band = None

    return {
        "identity": {
            "name": row["name"],
            "version": row["version"],
            "family": row["family"],
            "confidenceBand": confidence_band,
            "origin": row["origin"],
        },
        "evidence": evidence,
        "lineage": lineage,
        "consumers": consumers,
        "interface": {"kind": interface_kind},
        "versions": [{"v": row["version"], "verdict": evidence["gate"]["verdict"]}],
    }


def _custom_interface_kind(family: str) -> str:
    """Map a custom-model mode to an interface kind: python | container | rest."""
    if family == "docker":
        return "container"
    if family == "rest":
        return "rest"
    return "python"


def _custom_consumers(model_name: str) -> List[str]:
    return sorted(
        {
            r["campaign_id"]
            for r in _iter_custom_registrations()
            if r["model_name"] == model_name
        }
    )


# ─────────────────────────────────────────────────────────────────────────────
# Project-scoped track reads (Train / Adapt / Optimise)
# ─────────────────────────────────────────────────────────────────────────────
# These map three stores that ALREADY EXIST onto the frontend track contract:
#
#   Train    -> registered custom models per campaign are the "training runs"
#               that produced a scorer (custom_model_registrations).
#   Adapt    -> the customer before->after DPO pair recorder
#               (regulatory_pair_recorder: data/regulatory_training/dpo/*.jsonl).
#   Optimise -> the Bayesian-optimizer proposal rounds
#               (auto_retrain.list_auto_proposals over a campaign DB).
#
# They live under the DISTINCT `/api/model-tracks/*` prefix so they never
# collide with the greedy `/api/models/{model_id:path}` detail route. Same
# honesty contract as inference: a project with no such work returns an
# honest-empty payload, NEVER fabricated runs / pairs / rounds / scores.
#
# `project` maps to a campaign id where one applies; when it does not resolve to
# a real campaign the read is account-scope (all campaigns) or honest-empty.
def _resolve_campaign_ids(project: Optional[str]) -> List[str]:
    """Campaign ids to read. A matching project id first, else all campaigns."""
    all_ids = sorted({r["campaign_id"] for r in _iter_custom_registrations()})
    if project and project in all_ids:
        return [project]
    return all_ids


@router.get(
    "/api/model-tracks/train",
    summary="Training-runs list for the Train track (registered scorers per campaign).",
)
def train_track(project: Optional[str] = None) -> Dict[str, Any]:
    """
    The Train track lists two real training-run sources:

    1. Adaptation training jobs (regulatory_training_jobs) — including the
       retrains queued from the Adapt track. These carry a live status
       (queued/running/succeeded/failed) so a just-triggered retrain shows up
       here as it progresses.
    2. Registered custom scorers per campaign — each is the artefact of a
       training run that produced a scoring model.

    No metric is fabricated — when the thin layer has no measured metric we
    report an em-dash, not a number. Adaptation jobs come first (most recent
    first) so a fresh retrain is at the top.
    """
    runs: List[Dict[str, Any]] = []
    runs.extend(_adaptation_training_runs(project))

    regs = _iter_custom_registrations()
    ids = set(_resolve_campaign_ids(project))
    for r in regs:
        if r["campaign_id"] not in ids:
            continue
        enabled = r.get("enabled", 1)
        runs.append(
            {
                "name": r["model_name"],
                "family": r.get("mode", "custom"),
                "when": _fmt_ts(r.get("registered_at")),
                "status": "completed" if enabled else "failed",
                "gate": "registered" if enabled else "disabled",
                "metric": "—",  # no measured metric in this thin layer
                "dataset": r["campaign_id"],
                "version": f"→ {r['model_name']} v1",
                "modelId": _custom_model_id(r["campaign_id"], r["model_name"]),
            }
        )
    return {"runs": runs}


# Map the worker's job statuses to the Train track's status vocabulary.
_JOB_STATUS_MAP = {
    "queued": "queued",
    "running": "running",
    "succeeded": "completed",
    "failed": "failed",
    "cancelled": "failed",
}


def _adaptation_training_runs(project: Optional[str]) -> List[Dict[str, Any]]:
    """
    Adaptation training jobs from regulatory_training_jobs, most-recent first.
    org_id = project when supplied (the retrain endpoint submits with that org).
    Best-effort: a missing store yields [].
    """
    try:
        from galaxy.ai.drug_discovery import regulatory_training_jobs as rj
    except Exception as exc:  # noqa: BLE001
        log.debug("train: regulatory_training_jobs unavailable: %s", exc)
        return []

    try:
        # The store is keyed by user_id; the retrain endpoint uses project (or
        # "models-track") as both user and org. Read that user's jobs.
        user_id = project or "models-track"
        jobs = rj.list_for_user(user_id)
    except Exception as exc:  # noqa: BLE001
        log.debug("train: list_for_user failed: %s", exc)
        return []

    out: List[Dict[str, Any]] = []
    for j in jobs:
        status = _JOB_STATUS_MAP.get(getattr(j, "status", ""), "queued")
        out.append(
            {
                "name": f"adapt · {getattr(j, 'adaptation_mode', 'prompt_rules')}",
                "family": "adaptation",
                "when": _fmt_ts(getattr(j, "submitted_at", None)),
                "status": status,
                "gate": (getattr(j, "message", "") or status),
                "metric": f"{getattr(j, 'edit_pair_count', 0)} edit pairs",
                "dataset": getattr(j, "org_id", "") or "—",
                "version": getattr(j, "adapter_path", "") and "→ adapter written" or "",
                # No model object to open for an adaptation job in this layer.
            }
        )
    return out


@router.get(
    "/api/model-tracks/adapt",
    summary="Learned before->after edit pairs for the Adapt track (DPO pair recorder).",
)
def adapt_track(project: Optional[str] = None) -> Dict[str, Any]:
    """
    Reads the customer before->after DPO pairs the pair recorder appends. Each
    row is a switchable learned rule (before = model's original text, after =
    the customer's correction). Best-effort: a missing store is honest-empty.
    """
    pairs: List[Dict[str, Any]] = []
    try:
        rows = _read_dpo_pairs(project)
    except Exception as exc:  # noqa: BLE001 — best-effort read
        log.debug("model-tracks/adapt: read failed: %s", exc)
        rows = []
    disabled = _load_disabled_pairs()
    for i, row in enumerate(rows):
        meta = row.get("meta", {}) if isinstance(row, dict) else {}
        chosen = (row.get("chosen") or "").strip()
        rejected = (row.get("rejected") or "").strip()
        if not chosen and not rejected:
            continue
        section = meta.get("section_type") or meta.get("task") or "output"
        pair_id = meta.get("row_id") or f"pair-{i+1}"
        pairs.append(
            {
                "id": pair_id,
                "learned": f"prefer your edit in {section}",
                "scope": meta.get("org_id") and "organisation" or "project",
                "before": rejected or "(model output)",
                "after": chosen or "(your edit)",
                "source": f"{section} · {_fmt_ts(meta.get('recorded_at'))}",
                # A recorded pair is active unless the persisted disabled-set
                # (a sidecar override the worker/compiler can consult) turns it
                # off. State round-trips: a toggle POST persists here.
                "on": pair_id not in disabled,
            }
        )
    # pendingCount = active (not-disabled) pairs awaiting the next retrain.
    active = sum(1 for p in pairs if p["on"])
    return {"pendingCount": active, "pairs": pairs}


# ── Adapt: persisted on/off override for learned pairs ───────────────────────
# The DPO pair store is append-only (the worker reads it); we NEVER mutate a
# recorded pair. A toggle is persisted as a separate append-only override log,
# coalesced to a current on/off per row_id. This is a real persisted decision
# the compiler can consult, not an in-memory flag.
def _disabled_pairs_path() -> str:
    import os
    from pathlib import Path

    try:
        from galaxy.ai.drug_discovery.regulatory_pair_recorder import PAIRS_PATH

        base = Path(PAIRS_PATH).parent
    except Exception:  # noqa: BLE001
        base = Path(
            os.environ.get(
                "BIOMATE_DPO_DIR",
                str(Path(__file__).resolve().parents[5] / "data" / "regulatory_training" / "dpo"),
            )
        )
    return str(base / "disabled_pairs.jsonl")


def _load_disabled_pairs() -> set:
    """Current disabled row_ids, coalesced from the append-only override log."""
    import json as _json
    import os

    path = _disabled_pairs_path()
    if not os.path.exists(path):
        return set()
    state: Dict[str, bool] = {}
    try:
        with open(path, "r") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    rec = _json.loads(line)
                except Exception:  # noqa: BLE001
                    continue
                rid = rec.get("row_id")
                if rid:
                    # disabled=True means "off"; the last write for a row wins.
                    state[rid] = bool(rec.get("disabled", True))
    except Exception as exc:  # noqa: BLE001
        log.debug("adapt: read disabled-set failed: %s", exc)
        return set()
    return {rid for rid, off in state.items() if off}


def _append_disabled_override(row_id: str, disabled: bool) -> None:
    import json as _json
    import os
    import time as _time
    from pathlib import Path

    path = _disabled_pairs_path()
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    rec = {"row_id": row_id, "disabled": bool(disabled), "at": _time.time()}
    with _disabled_lock:
        with open(path, "a") as f:
            f.write(_json.dumps(rec) + "\n")


_disabled_lock = threading.Lock()


@router.post(
    "/api/model-tracks/adapt/{pair_id}/toggle",
    summary="Persist a learned pair on/off (append-only override; never mutates the DPO store).",
)
def toggle_adapt_pair(pair_id: str, body: Optional[TogglePairRequest] = None) -> Dict[str, Any]:
    if not pair_id:
        raise HTTPException(status_code=400, detail="pair_id required")
    currently_disabled = pair_id in _load_disabled_pairs()
    # Explicit target if provided, else FLIP the current state: an enabled pair
    # (not disabled) toggles off; a disabled pair toggles back on.
    if body is not None and body.on is not None:
        want_on = bool(body.on)
    else:
        want_on = currently_disabled  # flip: was-off → on, was-on → off
    _append_disabled_override(pair_id, disabled=not want_on)
    return {"id": pair_id, "on": want_on}


@router.post(
    "/api/model-tracks/adapt/retrain",
    summary="Queue a retrain over the active edit pairs as a tracked training job.",
)
def retrain_adapt(project: Optional[str] = None) -> Dict[str, Any]:
    """
    Queues a real retrain job through regulatory_training_jobs.submit and advances
    it one worker tick. The default adaptation mode (prompt_rules) is cheap — it
    compiles the customer edit pairs into a per-org rule YAML in seconds with no
    GPU (regulatory_training_worker._do_prompt_rules) — so it is safe to run
    synchronously here; the job goes queued → running → succeeded and produces a
    real artefact the serving path loads on the next inference call. The job is
    then visible in the Train track (which reads the same jobs store).

    GPU modes (post_train_lora) are NOT started here — the worker itself refuses
    them without a harness witness, per CLAUDE.md "Review Code Before Testing".
    """
    org_id = project or "default"
    user_id = project or "models-track"  # per-user store; project stands in when no auth ctx
    try:
        from galaxy.ai.drug_discovery.regulatory_training_jobs import submit

        # DEFAULT_ADAPTATION_MODE is prompt_rules (cheap, no GPU).
        job = submit(user_id=user_id, org_id=org_id)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except Exception as exc:  # noqa: BLE001
        log.warning("adapt retrain submit failed: %s", exc)
        raise HTTPException(status_code=502, detail=f"retrain submit failed: {exc}")

    # Advance the freshly-queued job one worker tick so the retrain actually runs
    # (not left queued forever waiting for an out-of-band poller). Best-effort:
    # if the worker is unavailable the job stays queued and a running worker /
    # the `tick` CLI will pick it up later.
    final_status = getattr(job, "status", "queued")
    message = ""
    try:
        from galaxy.ai.drug_discovery.regulatory_training_worker import tick

        done = tick(max_jobs=5)  # drain this + any other queued jobs
        for j in done:
            if getattr(j, "job_id", None) == getattr(job, "job_id", None):
                final_status = getattr(j, "status", final_status)
                message = getattr(j, "message", "")
                break
    except Exception as exc:  # noqa: BLE001 — the queued job persists regardless
        log.debug("adapt retrain tick skipped: %s", exc)

    return {
        "job_id": getattr(job, "job_id", None),
        "status": final_status,
        "edit_pair_count": getattr(job, "edit_pair_count", None),
        "message": message,
    }


@router.get(
    "/api/model-tracks/optimise",
    summary="The DMTA loop for the Optimise track (Bayesian-optimizer proposal rounds).",
)
def optimise_track(project: Optional[str] = None) -> Dict[str, Any]:
    """
    Reads the latest optimizer proposal round for a campaign and shapes it as the
    DMTA loop. Returns {active: False} when there is no proposal round, so the
    frontend renders its honest empty state. No score is fabricated — scores and
    confidence come straight from the stored round.
    """
    campaign_ids = _resolve_campaign_ids(project)
    for campaign_id in campaign_ids:
        try:
            loop = _optimise_for_campaign(campaign_id)
        except Exception as exc:  # noqa: BLE001 — best-effort read
            log.debug("model-tracks/optimise: %s failed: %s", campaign_id, exc)
            continue
        if loop is not None:
            return loop
    return {"active": False}


def _optimise_for_campaign(campaign_id: str) -> Optional[Dict[str, Any]]:
    from pathlib import Path

    db_path = str(Path(_campaign_db_dir()) / f"{campaign_id}.db")
    if not Path(db_path).exists():
        return None
    try:
        from galaxy.ai.drug_discovery.auto_retrain import list_auto_proposals
    except Exception as exc:  # noqa: BLE001
        log.debug("optimise: auto_retrain unavailable: %s", exc)
        return None

    proposals = list_auto_proposals(db_path, campaign_id, limit=20)
    if not proposals:
        return None

    # The AutoProposal carries: round_number, proposed_smiles (list), scores
    # (dict keyed by objective → list, or by smiles), confidence_intervals, and
    # ad_statuses (list[str] parallel to proposed_smiles: "in_domain" /
    # "outside_domain"). We shape the LATEST round into the proposal table.
    latest = max(proposals, key=lambda p: getattr(p, "round_number", 0))
    round_no = getattr(latest, "round_number", 0)
    smiles = list(getattr(latest, "proposed_smiles", []) or [])
    scores = getattr(latest, "scores", {}) or {}
    cis = getattr(latest, "confidence_intervals", {}) or {}
    ad = list(getattr(latest, "ad_statuses", []) or [])

    # scores may be {objective: [per-compound]} or {smiles: score}. Resolve a
    # per-compound score list without fabricating a value when absent.
    per_compound_scores = _resolve_score_list(scores, smiles)

    proposal_rows: List[Dict[str, Any]] = []
    for i, smi in enumerate(smiles[:24]):
        sc = per_compound_scores[i] if i < len(per_compound_scores) else None
        conf = _confidence_from_ci(_ci_at(cis, smi, i))
        # Applicability-domain status → verdict. Outside the domain is a
        # safety-gate rejection, shown (not dropped) so the loop's intent stays
        # visible. Missing status defaults to in-domain (the optimizer default).
        status = ad[i] if i < len(ad) else "in_domain"
        verdict = (
            "accepted"
            if status == "in_domain"
            else "rejected · out of applicability domain"
        )
        proposal_rows.append(
            {
                "id": f"cand-{i+1}",
                "score": _fmt_num(sc),
                "confidence": conf,
                "verdict": verdict,
            }
        )

    rounds = [
        {
            "round": f"Round {getattr(p, 'round_number', 0)}",
            "status": "current" if getattr(p, "round_number", 0) == round_no else "closed",
            "what": f"{len(getattr(p, 'proposed_smiles', []) or [])} candidates",
            "when": _fmt_ts(getattr(p, "created_at", None)),
        }
        for p in sorted(proposals, key=lambda p: getattr(p, "round_number", 0))
    ]

    return {
        "active": True,
        "running": True,
        "round": round_no,
        "surrogates": [
            {"id": _custom_model_id(campaign_id, "surrogate-gp"), "label": "surrogate GP"}
        ],
        "rounds": rounds,
        "proposal": proposal_rows,
    }


def _resolve_score_list(scores: Any, smiles: List[str]) -> List[Any]:
    """
    Normalize the AutoProposal.scores field to a per-compound list aligned with
    `smiles`. scores may be {objective: [per-compound]} or {smiles: score}.
    Returns a list of length len(smiles) (None where unknown) — never fabricated.
    """
    if not isinstance(scores, dict) or not scores:
        return [None] * len(smiles)
    # {smiles: score}
    if any(s in scores for s in smiles):
        return [scores.get(s) for s in smiles]
    # {objective: [per-compound]} — take the first objective's list.
    for val in scores.values():
        if isinstance(val, (list, tuple)):
            out = list(val)
            if len(out) < len(smiles):
                out = out + [None] * (len(smiles) - len(out))
            return out[: len(smiles)]
    return [None] * len(smiles)


def _ci_at(cis: Any, smi: str, idx: int) -> Any:
    """Pull a (lo, hi) pair from confidence_intervals for a compound. None when absent."""
    if isinstance(cis, dict):
        if smi in cis:
            return cis[smi]
        lo = cis.get("lo") or cis.get("lower")
        hi = cis.get("hi") or cis.get("upper")
        if isinstance(lo, (list, tuple)) and isinstance(hi, (list, tuple)):
            if idx < len(lo) and idx < len(hi):
                return (lo[idx], hi[idx])
    elif isinstance(cis, (list, tuple)) and idx < len(cis):
        return cis[idx]
    return None


def _read_dpo_pairs(project: Optional[str]) -> List[Dict[str, Any]]:
    """
    Read the customer before->after DPO pairs from the recorder's JSONL store.
    Filters by org/project when the meta carries a matching org_id. Best-effort:
    a missing file returns [].
    """
    import json as _json

    try:
        from galaxy.ai.drug_discovery.regulatory_pair_recorder import PAIRS_PATH
        path = str(PAIRS_PATH)
    except Exception as exc:  # noqa: BLE001
        log.debug("adapt: pair recorder unavailable: %s", exc)
        return []

    import os

    if not os.path.exists(path):
        return []
    out: List[Dict[str, Any]] = []
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                row = _json.loads(line)
            except Exception:  # noqa: BLE001 — skip a corrupt line
                continue
            if project:
                org = (row.get("meta", {}) or {}).get("org_id")
                if org and org != project:
                    continue
            out.append(row)
    return out


def _confidence_from_ci(ci: Any) -> str:
    """Map a confidence-interval width to a low/medium/high band. Neutral when unknown."""
    try:
        lo, hi = ci[0], ci[1]
        width = abs(float(hi) - float(lo))
    except Exception:  # noqa: BLE001
        return "medium"
    if width <= 0.1:
        return "high"
    if width <= 0.3:
        return "medium"
    return "low"


def _fmt_num(v: Any) -> str:
    try:
        return f"{float(v):.3g}"
    except Exception:  # noqa: BLE001
        return "—"


def _fmt_ts(ts: Any) -> str:
    """Unix ts (or ISO string) -> a short date. Em-dash when unknown."""
    if not ts:
        return "—"
    if isinstance(ts, str):
        return ts[:10]
    try:
        import datetime as _dt

        return _dt.datetime.utcfromtimestamp(float(ts)).strftime("%Y-%m-%d")
    except Exception:  # noqa: BLE001
        return "—"


# ─────────────────────────────────────────────────────────────────────────────
# POST /api/models/{id}/infer
# ─────────────────────────────────────────────────────────────────────────────
@router.post(
    "/api/models/{model_id:path}/infer",
    summary="Dispatch a pre-trained inference; returns a run_id to poll.",
)
def infer(model_id: str, body: InferRequest) -> Dict[str, Any]:
    row = _find_catalog_row(model_id)
    if row is None:
        raise HTTPException(status_code=404, detail=f"Unknown model id: {model_id}")

    evidence_class = _evidence_class_for(model_id)
    run_id = _new_run(model_id, evidence_class)
    inputs = body.inputs or {}

    # Synchronous dispatch: each backend call already polls internally
    # (BioNeMo NVCF) or is fast (custom scorers). Result is stored under run_id
    # for the polling GET. On any failure we store a labelled stub of the right
    # shape so the frontend can still render.
    try:
        if model_id.startswith(_BIONEMO_PREFIX):
            result = _dispatch_bionemo(model_id, evidence_class, inputs)
        else:
            result = _dispatch_custom(model_id, inputs)
        _finish_run(run_id, result)
    except HTTPException:
        # Input-validation errors (missing 'sequence'/'smiles') are real client
        # errors — surface them, don't mask with a stub.
        _fail_run(run_id, "invalid inputs")
        raise
    except Exception as exc:  # noqa: BLE001
        log.warning("models: inference %s failed, returning stub: %s", model_id, exc)
        stub = _stub_result(evidence_class, reason=f"backend error: {exc}")
        # A stub is a completed run with clearly-labelled non-real output.
        _finish_run(run_id, stub)

    return {"run_id": run_id}


# ─────────────────────────────────────────────────────────────────────────────
# GET /api/inference/{run_id}/result
# ─────────────────────────────────────────────────────────────────────────────
@router.get(
    "/api/inference/{run_id}/result",
    summary="Inference result, shaped by evidence class.",
)
def get_inference_result(run_id: str) -> Dict[str, Any]:
    rec = _store().get_run(run_id)
    if rec is None:
        raise HTTPException(status_code=404, detail=f"Unknown run_id: {run_id}")

    if rec.get("status") == "running":
        return {"run_id": run_id, "status": "running"}
    if rec.get("status") == "failed":
        return {"run_id": run_id, "status": "failed", "error": rec.get("error")}

    result = rec.get("result") or {}
    return {
        "run_id": run_id,
        "status": "completed",
        "evidenceClass": rec.get("evidence_class"),
        **result,
    }


# ─────────────────────────────────────────────────────────────────────────────
# Dispatch: BioNeMo
# ─────────────────────────────────────────────────────────────────────────────
def _dispatch_bionemo(
    model_id: str, evidence_class: str, inputs: Dict[str, Any]
) -> Dict[str, Any]:
    """
    Dispatch a BioNeMo-covered model. Returns a result already shaped by
    evidence class. Falls back to a labelled stub when the NIM is unreachable.
    """
    fn_name = model_id[len(_BIONEMO_PREFIX):]

    try:
        from galaxy.ai.bionemo_client import BioNeMoClient, MODE_STUB

        client = BioNeMoClient()
    except Exception as exc:  # noqa: BLE001
        return _stub_result(evidence_class, reason=f"BioNeMo client init failed: {exc}")

    # The client owns backend selection (self_host | hosted_api | stub) — do NOT
    # re-gate on NVIDIA_API_KEY here: production mode is self_host (a URL, no key),
    # so a key-only check would stub out every inference even with the NIM up.
    # When nothing is configured the client's effective mode is stub; surface its
    # own honest reason. Otherwise dispatch and let per-call stub handling (below)
    # label an unreachable backend.
    if client._effective_mode() == MODE_STUB:
        return _stub_result(
            evidence_class, reason=client._stub_reason(fn_name, MODE_STUB)
        )

    if evidence_class == STRUCTURE:
        return _bionemo_structure(client, fn_name, inputs)
    if evidence_class == GENOMIC:
        return _bionemo_genomic(client, fn_name, inputs)
    if evidence_class == CHEMICAL:
        # No BioNeMo chemical model is wired into this catalog yet.
        return _stub_result(evidence_class, reason="no BioNeMo chemical model wired")
    return _stub_result(evidence_class, reason="unknown evidence class")


def _bionemo_structure(client, fn_name: str, inputs: Dict[str, Any]) -> Dict[str, Any]:
    sequence = inputs.get("sequence") or inputs.get("seq")
    if not sequence:
        raise HTTPException(status_code=400, detail="structure inference requires 'sequence'")

    if fn_name == "esmfold":
        pdb = client.esmfold(sequence)
        # ESMFold returns a PDB string ('' when the backend is unreachable —
        # never a fabricated structure). Label the empty case as a stub so the
        # UI shows "backend unreachable", not an empty-but-real prediction.
        if not pdb:
            return _stub_result(STRUCTURE, reason="ESMFold backend unreachable")
        # per-residue pLDDT lives in the B-factor column.
        plddt = _plddt_from_pdb(pdb)
        return {
            "structureFileRef": _store_blob(pdb, suffix=".pdb"),
            "plddt": plddt,
            "pae": [],  # ESMFold does not emit PAE
            "regions": [],
        }

    # boltz2 / alphafold2 / openfold2 → dict payloads (CIF + confidence).
    # Route through the mode-aware entry points so self_host / stub are honoured
    # (openfold2 must NOT call _nvcf_call directly — that bypasses self_host and
    # leaks data to NVIDIA's hosted API contrary to the data-residency posture).
    if fn_name == "boltz2":
        raw = client.boltz2(sequence)
    elif fn_name == "alphafold2":
        raw = client.alphafold2(sequence)
    else:
        raw = client._call(fn_name, {"sequence": sequence})  # openfold2 etc.

    # An unreachable backend returns a labelled stub dict — surface it as such.
    if client._is_stub(raw):
        return _stub_result(STRUCTURE, reason=raw.get("reason", "backend unreachable"))

    # Locate the structure list. Models disagree on the key AND the entry shape:
    #   boltz2      → "structures": ["<cif str>"] or [{"structure": "<cif>"}]
    #   openfold2   → "structures_in_ranked_order": [{"structure", "plddt":[…],
    #                 "predicted_aligned_error":[…], …}]
    #   (self-host) → "pdbs": ["<pdb str>"]
    structures = (
        raw.get("structures")
        or raw.get("pdbs")
        or raw.get("structures_in_ranked_order")
        or []
    )
    _first = structures[0] if structures else ""
    entry = _first if isinstance(_first, dict) else {}
    struct_str = (
        (entry.get("structure") or entry.get("cif") or entry.get("pdb") or "")
        if entry else (_first or "")
    )
    if not isinstance(struct_str, str):
        struct_str = ""

    def _perres(v):
        # A usable per-residue array — a real list of >1 values, not a global scalar.
        return list(v) if isinstance(v, (list, tuple)) and len(v) > 1 else None

    # Per-residue pLDDT: prefer an explicit per-residue array on the structure
    # entry (openfold2 gives plddt[]); else parse the CIF/PDB B-factor column
    # (boltz2 writes it there). NEVER the global confidence scalar — that produced
    # a single-point "pLDDT" chart.
    plddt = (
        _perres(entry.get("plddt"))
        or _plddt_from_structure(struct_str)
        or _perres(raw.get("plddt"))
        or []
    )
    pae = (
        entry.get("predicted_aligned_error")
        or entry.get("pae")
        or raw.get("pae")
        or raw.get("predicted_aligned_error")
        or []
    )
    return {
        "structureFileRef": _store_blob(struct_str, suffix=".cif"),
        "plddt": plddt,
        "pae": pae,
        "regions": [],
    }


def _bionemo_genomic(client, fn_name: str, inputs: Dict[str, Any]) -> Dict[str, Any]:
    sequence = inputs.get("sequence") or inputs.get("seq")
    if not sequence:
        raise HTTPException(status_code=400, detail="genomic inference requires 'sequence'")
    locus = inputs.get("locus", "user-supplied")
    num_tokens = int(inputs.get("num_tokens", 100))

    raw = client.evo2_generate(sequence, num_tokens=num_tokens, model=fn_name)
    if client._is_stub(raw):
        return _stub_result(GENOMIC, reason=raw.get("reason", "backend unreachable"))
    generated = raw.get("sequence", "")
    # Evo2 emits a generated sequence; we expose it as a 'marks' track over the
    # generated region. No per-base scores are fabricated.
    tracks: List[Dict[str, Any]] = []
    if generated:
        tracks.append(
            {
                "kind": "marks",
                "name": "evo2_generated",
                "intervals": [
                    {"start": len(sequence), "end": len(sequence) + len(generated)}
                ],
            }
        )
    return {
        "locus": locus,
        "tracks": tracks,
        "flagged": [],
    }


# ─────────────────────────────────────────────────────────────────────────────
# Dispatch: custom (chemical)
# ─────────────────────────────────────────────────────────────────────────────
def _dispatch_custom(model_id: str, inputs: Dict[str, Any]) -> Dict[str, Any]:
    """
    Dispatch a registered custom scoring model over a SMILES list. Returns a
    chemical-shaped result. A custom model must be re-registered in-process to
    actually run (CustomModelRegistry keeps wrappers in memory) — if it is not
    loaded, we return a labelled stub of the correct shape.
    """
    parsed = _parse_custom_id(model_id)
    if parsed is None:
        raise HTTPException(status_code=400, detail=f"Malformed custom id: {model_id}")
    campaign_id, model_name = parsed

    smiles_list = inputs.get("smiles") or inputs.get("inputs") or []
    if isinstance(smiles_list, str):
        smiles_list = [smiles_list]
    if not smiles_list:
        raise HTTPException(status_code=400, detail="chemical inference requires 'smiles'")

    try:
        from galaxy.ai.drug_discovery.custom_model_registry import CustomModelRegistry

        registry = CustomModelRegistry(_campaign_db(campaign_id))
        scores, _record = registry.run_named_model(campaign_id, model_name, smiles_list)
    except KeyError as exc:
        # Model registered in DB but not loaded in this process — expected;
        # return a labelled stub of the right shape.
        return _stub_result(
            CHEMICAL,
            reason=f"custom model not loaded in-process: {exc}",
            smiles_list=smiles_list,
        )
    except HTTPException:
        raise
    except Exception as exc:  # noqa: BLE001
        return _stub_result(CHEMICAL, reason=f"custom scorer failed: {exc}",
                            smiles_list=smiles_list)

    hits: List[Dict[str, Any]] = []
    for i, smi in enumerate(smiles_list):
        score = scores.get(smi)
        hits.append(
            {
                "id": f"cmpd-{i+1}",
                "smiles": smi,
                "score": score,
                "confidence": "medium",  # provenance-neutral; not a measured band
                "herg": None,
                "drugLike": None,
                "verdict": "held",  # no gate applied in this thin layer
            }
        )
    return {"hits": hits}


def _campaign_db(campaign_id: str) -> str:
    from pathlib import Path

    safe_id = "".join(c for c in campaign_id if c.isalnum() or c in "-_")
    if not safe_id:
        raise HTTPException(status_code=400, detail="Invalid campaign_id")
    d = _campaign_db_dir()
    Path(d).mkdir(parents=True, exist_ok=True)
    return str(Path(d) / f"{safe_id}.db")


# ─────────────────────────────────────────────────────────────────────────────
# Stub payloads — correct SHAPE, clearly labelled, never fabricated science.
# ─────────────────────────────────────────────────────────────────────────────
def _stub_result(
    evidence_class: str,
    reason: str,
    smiles_list: Optional[List[str]] = None,
) -> Dict[str, Any]:
    base: Dict[str, Any] = {"stub": True, "stub_reason": reason}

    if evidence_class == STRUCTURE:
        base.update(
            {
                "structureFileRef": None,
                "plddt": [],
                "pae": [],
                "regions": [],
            }
        )
    elif evidence_class == GENOMIC:
        base.update(
            {
                "locus": None,
                "tracks": [],
                "flagged": [],
            }
        )
    elif evidence_class == CHEMICAL:
        hits = []
        for i, smi in enumerate(smiles_list or []):
            hits.append(
                {
                    "id": f"cmpd-{i+1}",
                    "smiles": smi,
                    "score": None,  # NOT fabricated
                    "confidence": "low",
                    "herg": None,
                    "drugLike": None,
                    "verdict": "held",
                }
            )
        base.update({"hits": hits})
    return base


# ─────────────────────────────────────────────────────────────────────────────
# Small helpers
# ─────────────────────────────────────────────────────────────────────────────
def _plddt_from_pdb(pdb_or_cif: str) -> List[float]:
    """
    Extract per-residue pLDDT from a PDB string (B-factor of CA atoms).
    Returns [] for empty/non-PDB input. These are REAL model outputs when the
    backend returns a structure — not fabricated.
    """
    if not pdb_or_cif or "ATOM" not in pdb_or_cif:
        return []
    out: List[float] = []
    for line in pdb_or_cif.splitlines():
        if line.startswith("ATOM") and line[12:16].strip() == "CA":
            try:
                out.append(float(line[60:66]))
            except (ValueError, IndexError):
                continue
    return out


def _plddt_from_cif(cif: str) -> List[float]:
    """
    Extract per-residue pLDDT from an mmCIF string (``_atom_site.B_iso_or_equiv``
    of CA atoms). boltz2 / AlphaFold2 / OpenFold2 write per-residue pLDDT into the
    B-factor column of the CIF they return. Returns [] for empty / non-CIF input.
    Column order is read from the ``_atom_site.*`` loop header, so it is robust to
    field-order differences between models. Real model output — never fabricated.
    """
    if not cif or "_atom_site." not in cif:
        return []
    cols: List[str] = []
    out: List[float] = []
    for line in cif.splitlines():
        s = line.strip()
        if s.startswith("_atom_site."):
            cols.append(s.split(".", 1)[1])
            continue
        if cols and (s.startswith("ATOM") or s.startswith("HETATM")):
            fields = s.split()
            if len(fields) < len(cols):
                continue
            rec = dict(zip(cols, fields))
            atom = (rec.get("label_atom_id") or rec.get("auth_atom_id") or "").strip('"\'')
            if atom == "CA":
                try:
                    out.append(float(rec.get("B_iso_or_equiv", "")))
                except (ValueError, TypeError):
                    continue
    return out


def _plddt_from_structure(struct: str) -> List[float]:
    """Per-residue pLDDT from a structure blob — tries mmCIF then PDB."""
    return _plddt_from_cif(struct) or _plddt_from_pdb(struct)


def _store_blob(content: str, suffix: str) -> Optional[str]:
    """
    Persist a structure blob to a temp file and return a file ref the frontend /
    DL viewer can fetch. Returns None for empty content. Best-effort — the ref
    is a path the existing static/file endpoints can serve.
    """
    if not content:
        return None
    import os
    import tempfile

    out_dir = os.environ.get(
        "BIOMATE_INFERENCE_OUT_DIR", tempfile.gettempdir()
    )
    try:
        os.makedirs(out_dir, exist_ok=True)
        fname = f"inference-{uuid.uuid4().hex[:12]}{suffix}"
        path = os.path.join(out_dir, fname)
        with open(path, "w") as f:
            f.write(content)
        return path
    except Exception as exc:  # noqa: BLE001
        log.warning("models: could not store structure blob: %s", exc)
        return None
