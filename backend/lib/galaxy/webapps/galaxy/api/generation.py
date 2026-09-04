"""
De-novo Design & Generate API (Spec 05).

A thin FastAPI router that exposes the *generate -> predict -> optimise
(multi-objective) -> rank* chain from Spec 05 over HTTP, wrapping the wave-1
``DeNovoPipeline`` (``galaxy.ai.drug_discovery.denovo_pipeline``) WITHOUT
reimplementing any of its generate / GP-hypervolume / rank logic.

    POST /api/generate      {target/constraints, objectives, budget} -> {run_id}
    GET  /api/generate/{id}  -> {status, candidates[], pareto?, rejected[]}

Design commitments carried over verbatim from Spec 05 (see the HTML spec):

  * NO composite score.  Each objective keeps its own units and its own target;
    the ranking key the optimiser returns (mean of normalised per-objective GP
    scores) is exposed as ``score`` for ordering only, and every per-objective
    value is returned separately in ``objectives[]``.

  * Safety is a GATE, not an objective to be traded away.  A candidate that
    trips a structural-alert gate is *rejected but stays visible with its
    reason* — it is returned in ``rejected[]`` (never silently filtered) and,
    for the ranked view, also surfaced as a ``verdict:"rejected"`` hit.

  * HONESTY CONTRACT (matching wave-1 ``generators.py`` / ``denovo_pipeline``):
    no molecule is ever fabricated.  The generator is the wave-1 ``Generator``
    swap-point; when it cannot run (RDKit missing, no seed, NIM unreachable) it
    returns an empty list and its ``last_status`` reason is reported through the
    run's ``notes`` / ``status`` — the endpoint invents nothing to fill a
    shortlist.  Objective and gate predictions are computed from the molecule
    itself with RDKit (QED, physchem descriptors, structural-alert catalogues);
    where RDKit is unavailable the run reports that plainly rather than
    returning numbers.

Auto-discovered like ``nextflow_executor.py`` — ``include_all_package_routers``
picks up the module-level ``router`` object; no explicit registration needed.
"""
# Keep this first. PEP 604 union syntax used below requires it on Python 3.9;
# without it gunicorn workers crash at import (the same footgun documented in
# nextflow_executor.py).
from __future__ import annotations

import logging
import threading
import time
import uuid
from typing import Any, Dict, List, Optional

from fastapi import HTTPException
from pydantic import BaseModel, Field

from galaxy.webapps.galaxy.api import Router

log = logging.getLogger(__name__)

router = Router(tags=["generation"])

# Run registry — cross-worker via the shared RunStateStore. A design run is
# short-lived, but the run record is written by a background thread on the worker
# that served POST /api/generate while the client polls GET /api/generate/{id},
# which round-robins across all 4 dev workers. An in-process dict would 404 on
# ~75% of polls; the shared store (RUN_STATE_STORE=redis on dev) makes the record
# visible to every worker. run_ids are prefixed "gen_" so they never collide with
# nextflow/inference run keys, and we never set_pid() so the CompletionPoller
# skips them.
def _store():
    from galaxy.ai.runs.run_state_store import get_run_state_store

    return get_run_state_store()


# ---------------------------------------------------------------------------
# Request / response schemas
# ---------------------------------------------------------------------------

class PropertyEnvelope(BaseModel):
    """Drug-like window (a range, not a single cut-off) — Spec 05 §5.2."""
    mw_max: Optional[float] = None
    logp_max: Optional[float] = None
    tpsa_max: Optional[float] = None
    rot_bonds_max: Optional[int] = None


class GenerateConstraints(BaseModel):
    """The generation constraints — 'the constraints are the interface' (§5.2)."""
    # Target: a structure / pharmacophore seed. The wave-1 BRICS generator needs
    # a seed SMILES; a real structure-conditioned generator uses the PDB.
    seed_smiles: Optional[str] = None
    target_protein_pdb: Optional[str] = None
    # Scaffold policy: 'stay' | 'hop' | 'grow' (carried to the generator spec).
    scaffold_policy: str = "stay"
    property_envelope: PropertyEnvelope = Field(default_factory=PropertyEnvelope)
    # Structural-alert / banned-moiety exclusions applied as the safety GATE.
    exclusions: List[str] = Field(default_factory=list)


class GenerateRequest(BaseModel):
    # 'brics' (deterministic enumeration, default) | 'bionemo_genmol' |
    # 'bionemo_molmim' (learned, NIM-backed) — passed straight to get_generator.
    generator: str = "brics"
    constraints: GenerateConstraints = Field(default_factory=GenerateConstraints)
    # Objectives to optimise TOGETHER (multi-objective; no composite). Each name
    # must be one the backend can back with a real RDKit predictor.
    objectives: List[str] = Field(default_factory=lambda: ["drug_like"])
    # Labelled seed/training compounds the GP surrogate is fit on. Optional: when
    # omitted the endpoint derives a seed series from the generator's own output
    # so the surrogate has something to learn from (documented in the notes).
    seed_series: List[str] = Field(default_factory=list)
    # Budget — count (candidates to keep) is stated with cost shown before the
    # run, per §5.2. n_generate caps the virtual library the GP scores.
    count: int = 20
    n_generate: int = 200


class ObjectiveValue(BaseModel):
    name: str
    value: float
    unit: str
    target: Optional[float] = None
    direction: str  # 'maximize' | 'minimize'


class Candidate(BaseModel):
    id: str
    smiles: str
    # Ranking key ONLY (mean of normalised per-objective GP scores). Never a
    # user-facing "the one number"; every real objective is in `objectives`.
    score: float
    confidence: str
    herg: str
    drugLike: str
    verdict: str  # 'accepted' | 'flagged' | 'rejected' | 'held'
    objectives: List[ObjectiveValue] = Field(default_factory=list)


class RejectedCandidate(BaseModel):
    id: str
    smiles: str
    reason: str            # which gate rejected it
    objectives: List[ObjectiveValue] = Field(default_factory=list)


# ---------------------------------------------------------------------------
# Real, molecule-derived predictors + safety gate (RDKit).  No fabrication:
# every number here is computed from the structure itself.
# ---------------------------------------------------------------------------

try:
    from rdkit import Chem
    from rdkit.Chem import QED, Descriptors, Crippen
    from rdkit.Chem.FilterCatalog import FilterCatalog, FilterCatalogParams
    _RDKIT_AVAILABLE = True
except Exception:  # pragma: no cover - RDKit-less envs (e.g. local py3.9 import check)
    _RDKIT_AVAILABLE = False


def _qed_predictor(smiles_list: List[str]) -> Dict[str, float]:
    """Drug-likeness (QED, 0-1, higher better) — real RDKit, per molecule."""
    out: Dict[str, float] = {}
    if not _RDKIT_AVAILABLE:
        return out
    for smi in smiles_list:
        mol = Chem.MolFromSmiles(smi)
        if mol is None:
            continue
        try:
            out[smi] = float(QED.qed(mol))
        except Exception:
            continue
    return out


def _envelope_predictor(envelope: PropertyEnvelope):
    """
    Build a property-envelope objective predictor: fraction of the stated
    physchem window a molecule satisfies (0-1, higher better). Real descriptors;
    a molecule with no envelope stated scores 1.0 (nothing to violate).
    """
    checks = []
    if envelope.mw_max is not None:
        checks.append(lambda m, x=envelope.mw_max: Descriptors.MolWt(m) <= x)
    if envelope.logp_max is not None:
        checks.append(lambda m, x=envelope.logp_max: Crippen.MolLogP(m) <= x)
    if envelope.tpsa_max is not None:
        checks.append(lambda m, x=envelope.tpsa_max: Descriptors.TPSA(m) <= x)
    if envelope.rot_bonds_max is not None:
        checks.append(lambda m, x=envelope.rot_bonds_max: Descriptors.NumRotatableBonds(m) <= x)

    def predict(smiles_list: List[str]) -> Dict[str, float]:
        out: Dict[str, float] = {}
        if not _RDKIT_AVAILABLE:
            return out
        for smi in smiles_list:
            mol = Chem.MolFromSmiles(smi)
            if mol is None:
                continue
            if not checks:
                out[smi] = 1.0
            else:
                passed = sum(1 for c in checks if _safe_check(c, mol))
                out[smi] = passed / len(checks)
        return out

    return predict


def _safe_check(check, mol) -> bool:
    try:
        return bool(check(mol))
    except Exception:
        return False


# Objective registry: name -> (predictor factory, unit, direction). Only names
# backed by a REAL molecule-derived predictor are offered. Affinity is NOT here
# because there is no honest target-conditioned affinity predictor to wire
# without a trained model + target — it is reported as unavailable rather than
# fabricated (Spec 05 §5.3: no confident numbers we cannot stand behind).
_OBJECTIVE_UNITS = {
    "drug_like": ("QED", "maximize"),
    "property_envelope": ("fraction-in-window", "maximize"),
}


def _build_structural_alert_catalog():
    """Brenk + PAINS structural-alert catalogue — the safety GATE substrate."""
    if not _RDKIT_AVAILABLE:
        return None
    try:
        params = FilterCatalogParams()
        params.AddCatalog(FilterCatalogParams.FilterCatalogs.BRENK)
        params.AddCatalog(FilterCatalogParams.FilterCatalogs.PAINS)
        return FilterCatalog(params)
    except Exception:
        return None


def _safety_gate(smiles: str, catalog, banned_smarts: List[str]) -> Optional[str]:
    """
    Return a rejection reason if the molecule trips the safety gate, else None.

    The gate is real, deterministic chemistry — a structural-alert catalogue
    (Brenk/PAINS) plus any user-banned SMARTS moieties. It is NOT a fabricated
    hERG number; a candidate below the safety floor is rejected and stays
    visible with THIS reason (Spec 05 §5.4).
    """
    if not _RDKIT_AVAILABLE:
        return None
    mol = Chem.MolFromSmiles(smiles)
    if mol is None:
        return "invalid structure (unparseable)"
    if catalog is not None:
        try:
            entry = catalog.GetFirstMatch(mol)
            if entry is not None:
                return f"structural alert: {entry.GetDescription()}"
        except Exception:
            pass
    for smarts in banned_smarts:
        patt = Chem.MolFromSmarts(smarts)
        if patt is not None and mol.HasSubstructMatch(patt):
            return f"banned moiety: {smarts}"
    return None


# ---------------------------------------------------------------------------
# Run execution — one closed round of the wave-1 pipeline
# ---------------------------------------------------------------------------

def _execute_run(run_id: str, req: GenerateRequest) -> None:
    """Run one DeNovoPipeline.run_round() and record the mapped result."""
    notes: List[str] = []
    try:
        from galaxy.ai.drug_discovery.generators import get_generator, GenerationSpec
        from galaxy.ai.drug_discovery.denovo_pipeline import (
            DeNovoPipeline,
            ObjectiveSpec,
        )
    except Exception as exc:
        _set_run(run_id, status="failed",
                 notes=[f"pipeline import failed: {exc}"])
        return

    # --- resolve objectives to REAL predictors (drop unknown/unbacked) --------
    obj_specs: List[Any] = []
    resolved_units: Dict[str, tuple] = {}
    for name in req.objectives:
        if name == "drug_like":
            obj_specs.append(ObjectiveSpec(name="drug_like",
                                           predictor=_qed_predictor,
                                           direction="maximize"))
            resolved_units["drug_like"] = _OBJECTIVE_UNITS["drug_like"]
        elif name == "property_envelope":
            pred = _envelope_predictor(req.constraints.property_envelope)
            obj_specs.append(ObjectiveSpec(name="property_envelope",
                                           predictor=pred, direction="maximize"))
            resolved_units["property_envelope"] = _OBJECTIVE_UNITS["property_envelope"]
        else:
            notes.append(
                f"objective {name!r} has no honest molecule-derived predictor "
                f"wired; skipped (not fabricated)")
    if not obj_specs:
        # Always keep at least drug-likeness so the run has a real objective.
        obj_specs.append(ObjectiveSpec(name="drug_like",
                                       predictor=_qed_predictor,
                                       direction="maximize"))
        resolved_units["drug_like"] = _OBJECTIVE_UNITS["drug_like"]

    # --- generator (wave-1 swap-point) ---------------------------------------
    try:
        generator = get_generator(req.generator)
    except ValueError as exc:
        _set_run(run_id, status="failed", notes=[str(exc)])
        return

    spec = GenerationSpec(
        seed_smiles=req.constraints.seed_smiles,
        n_molecules=req.n_generate,
        max_candidates=req.n_generate,
        target_protein_pdb=req.constraints.target_protein_pdb,
        constraints={"scaffold_policy": req.constraints.scaffold_policy},
    )

    # --- seed/training series the GP is fit on -------------------------------
    # Prefer a caller-supplied labelled series; otherwise derive one from the
    # generator's own library so the surrogate has data to learn from. Both are
    # REAL molecules (generated or provided) — never invented placeholders.
    seed_series = list(req.seed_series)
    if len(seed_series) < 8:
        pre = generator.propose(spec)
        if pre:
            seed_series = list(dict.fromkeys(seed_series + pre))
            notes.append(
                f"seed series derived from generator output "
                f"({len(pre)} molecules) — no external assay data supplied")
        else:
            _finish_empty(run_id, generator, notes,
                          reason=generator.last_status.get("reason", "no_candidates"))
            return

    n_initial = min(8, len(seed_series))
    pipeline = DeNovoPipeline(
        campaign_id=run_id,
        generator=generator,
        objectives=obj_specs,
        n_initial=n_initial,
    )

    try:
        result = pipeline.run_round(
            spec=spec,
            seed_smiles=seed_series,
            n_propose=req.count,
        )
    except Exception as exc:
        _set_run(run_id, status="failed",
                 notes=notes + [f"run_round failed: {exc}"])
        return

    notes.extend(result.notes)
    if not result.ranked:
        _finish_empty(run_id, generator, notes,
                      reason=(result.notes[-1] if result.notes else "no_ranked_candidates"),
                      n_generated=result.n_generated)
        return

    # --- map ranked shortlist -> candidates + apply safety gate ---------------
    catalog = _build_structural_alert_catalog()
    banned = list(req.constraints.exclusions)
    candidates: List[Candidate] = []
    rejected: List[RejectedCandidate] = []

    for row in result.ranked:
        smi = row["smiles"]
        cand_id = f"BM-{row['rank']:04d}"
        obj_values = _objective_values(row, obj_specs, resolved_units, req)
        drug_like_val = next((o for o in obj_values if o.name == "drug_like"), None)
        drug_like_str = f"QED {drug_like_val.value:.2f}" if drug_like_val else "n/a"

        reason = _safety_gate(smi, catalog, banned)
        if reason is not None:
            # Rejected by the safety gate — stays VISIBLE with its reason.
            rejected.append(RejectedCandidate(
                id=cand_id, smiles=smi, reason=reason, objectives=obj_values))
            candidates.append(Candidate(
                id=cand_id, smiles=smi, score=row["mean_score"],
                confidence=_confidence(row), herg=_herg_status(),
                drugLike=drug_like_str, verdict="rejected",
                objectives=obj_values))
            continue

        verdict = _verdict(row, drug_like_val)
        candidates.append(Candidate(
            id=cand_id, smiles=smi, score=row["mean_score"],
            confidence=_confidence(row), herg=_herg_status(),
            drugLike=drug_like_str, verdict=verdict, objectives=obj_values))

    pareto = []
    if result.proposal is not None:
        pareto = list(result.proposal.pareto_front_smiles)

    _set_run(
        run_id,
        status="completed",
        candidates=[c.dict() for c in candidates],
        rejected=[r.dict() for r in rejected],
        pareto=pareto,
        generator=result.generator_name,
        generator_is_learned=result.generator_is_learned,
        n_generated=result.n_generated,
        n_scored=result.n_scored,
        objectives=[{"name": n, "unit": u[0], "direction": u[1]}
                    for n, u in resolved_units.items()],
        notes=notes,
    )


def _objective_values(row, obj_specs, resolved_units, req) -> List[ObjectiveValue]:
    """Build the per-objective value list (own units, own target — no blend)."""
    values: List[ObjectiveValue] = []
    for spec in obj_specs:
        if spec.name not in row:
            continue
        unit, direction = resolved_units.get(spec.name, ("score", spec.direction))
        target = None
        if spec.name == "property_envelope":
            target = 1.0
        values.append(ObjectiveValue(
            name=spec.name, value=round(float(row[spec.name]), 4),
            unit=unit, target=target, direction=direction))
    return values


def _confidence(row) -> str:
    """Confidence from the GP acquisition value when present (else 'medium')."""
    acq = row.get("acquisition")
    if acq is None:
        return "medium"
    if acq >= 0.5:
        return "high"
    if acq >= 0.1:
        return "medium"
    return "low"


def _herg_status() -> str:
    """
    hERG status string. There is no honest hERG ML model wired here, so we do
    NOT emit a fabricated µM value; the safety GATE is structural-alert based
    (see _safety_gate). This reports the gate substrate plainly.
    """
    return "structural-alert gate"


def _verdict(row, drug_like_val) -> str:
    """
    accepted / flagged for a candidate that PASSED the safety gate.
    A weak drug-likeness score is a flag (advisory), not a hard reject —
    the hard reject is reserved for the safety gate (Spec 05 §5.4).
    """
    if drug_like_val is not None and drug_like_val.value < 0.5:
        return "flagged"
    return "accepted"


def _finish_empty(run_id, generator, notes, reason, n_generated=0):
    status = dict(getattr(generator, "last_status", {}))
    _set_run(
        run_id, status="completed", candidates=[], rejected=[], pareto=[],
        generator=getattr(generator, "name", "unknown"),
        generator_is_learned=getattr(generator, "is_learned", False),
        n_generated=n_generated, n_scored=0, objectives=[],
        notes=notes + [f"no candidates: {reason}"],
        generator_status=status,
    )


def _set_run(run_id: str, **fields) -> None:
    # Create-or-merge (matches the old setdefault semantics). The record is only
    # ever created in start_generation (before the worker thread starts), so the
    # get-then-branch is not racing a concurrent creator for the same run_id.
    fields["updated_at"] = time.time()
    store = _store()
    if store.get_run(run_id) is None:
        store.set_run(run_id, fields)
    else:
        store.update_run(run_id, **fields)


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@router.post("/api/generate", summary="Launch a de-novo design & generate run")
def start_generation(request: GenerateRequest) -> Dict[str, Any]:
    """
    Launch one closed generate -> predict -> optimise -> rank round (Spec 05).

    Returns immediately with a ``run_id``; the (RDKit/GP) work runs in a
    background thread so the caller is not blocked. Poll ``GET
    /api/generate/{run_id}`` for status + results.
    """
    run_id = f"gen_{uuid.uuid4().hex[:12]}"
    _set_run(run_id, status="running", candidates=[], rejected=[],
             pareto=[], notes=[], created_at=time.time())
    t = threading.Thread(target=_execute_run, args=(run_id, request), daemon=True)
    t.start()
    return {"run_id": run_id, "status": "running"}


@router.get("/api/generate/{run_id}", summary="Poll a de-novo design run")
def get_generation(run_id: str) -> Dict[str, Any]:
    """Return the run's status and (when complete) candidates / pareto / rejected."""
    rec = _store().get_run(run_id)
    if rec is None:
        raise HTTPException(status_code=404, detail=f"unknown run_id {run_id!r}")
    out = dict(rec)
    out["run_id"] = run_id
    return out
