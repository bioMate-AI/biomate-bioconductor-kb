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
    "esmfold": {
        "name": "ESMFold",
        "family": "structure",
        "evidence_class": STRUCTURE,
        "version": "1.0",
        "interface": "rest",
    },
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


def _bionemo_available() -> bool:
    """True if a NVIDIA_API_KEY is present (necessary, not sufficient)."""
    import os

    return bool(os.environ.get("NVIDIA_API_KEY", ""))


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
# In-process inference run registry
# ─────────────────────────────────────────────────────────────────────────────
# run_id -> {status, evidence_class, model_id, result, error, created_at}
_infer_runs: Dict[str, Dict[str, Any]] = {}
_infer_lock = threading.Lock()


def _new_run(model_id: str, evidence_class: str) -> str:
    run_id = f"inf-{uuid.uuid4().hex[:12]}"
    with _infer_lock:
        _infer_runs[run_id] = {
            "run_id": run_id,
            "model_id": model_id,
            "evidence_class": evidence_class,
            "status": "running",
            "result": None,
            "error": None,
            "created_at": time.time(),
        }
    return run_id


def _finish_run(run_id: str, result: Dict[str, Any]) -> None:
    with _infer_lock:
        rec = _infer_runs.get(run_id)
        if rec is None:
            return
        rec["status"] = "completed"
        rec["result"] = result


def _fail_run(run_id: str, error: str) -> None:
    with _infer_lock:
        rec = _infer_runs.get(run_id)
        if rec is None:
            return
        rec["status"] = "failed"
        rec["error"] = error


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
for _m in (ModelSummary, InferRequest, InferResponse):
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
async def list_models() -> List[Dict[str, Any]]:
    return _catalog()


# ─────────────────────────────────────────────────────────────────────────────
# GET /api/models/{id}
# ─────────────────────────────────────────────────────────────────────────────
@router.get(
    "/api/models/{model_id:path}",
    summary="Model detail: identity, evidence, lineage, consumers, interface, versions.",
)
async def get_model(model_id: str) -> Dict[str, Any]:
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
# POST /api/models/{id}/infer
# ─────────────────────────────────────────────────────────────────────────────
@router.post(
    "/api/models/{model_id:path}/infer",
    summary="Dispatch a pre-trained inference; returns a run_id to poll.",
)
async def infer(model_id: str, body: InferRequest) -> Dict[str, Any]:
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
async def get_inference_result(run_id: str) -> Dict[str, Any]:
    with _infer_lock:
        rec = _infer_runs.get(run_id)
        if rec is None:
            raise HTTPException(status_code=404, detail=f"Unknown run_id: {run_id}")
        rec = dict(rec)  # shallow copy for read outside the lock

    if rec["status"] == "running":
        return {"run_id": run_id, "status": "running"}
    if rec["status"] == "failed":
        return {"run_id": run_id, "status": "failed", "error": rec["error"]}

    result = rec["result"] or {}
    return {
        "run_id": run_id,
        "status": "completed",
        "evidenceClass": rec["evidence_class"],
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

    if not _bionemo_available():
        return _stub_result(
            evidence_class,
            reason="NVIDIA_API_KEY not set — BioNeMo NIM unreachable",
        )

    try:
        from galaxy.ai.bionemo_client import BioNeMoClient

        client = BioNeMoClient()
    except Exception as exc:  # noqa: BLE001
        return _stub_result(evidence_class, reason=f"BioNeMo client init failed: {exc}")

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
        # ESMFold returns a PDB string; per-residue pLDDT lives in the B-factor
        # column. We surface the file ref and parse pLDDT if present.
        plddt = _plddt_from_pdb(pdb)
        return {
            "structureFileRef": _store_blob(pdb, suffix=".pdb"),
            "plddt": plddt,
            "pae": [],  # ESMFold does not emit PAE
            "regions": [],
        }

    # boltz2 / alphafold2 / openfold2 → dict payloads (CIF + confidence)
    if fn_name == "boltz2":
        raw = client.boltz2(sequence)
    elif fn_name == "alphafold2":
        raw = client.alphafold2(sequence)
    else:
        raw = client._nvcf_call(fn_name, {"sequence": sequence})  # openfold2 etc.

    structures = raw.get("structures") or raw.get("pdbs") or []
    struct_str = structures[0] if structures else ""
    plddt = (
        raw.get("plddt")
        or raw.get("confidence_scores")
        or _plddt_from_pdb(struct_str)
    )
    pae = raw.get("pae") or raw.get("predicted_aligned_error") or []
    return {
        "structureFileRef": _store_blob(struct_str, suffix=".cif"),
        "plddt": list(plddt) if plddt else [],
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
