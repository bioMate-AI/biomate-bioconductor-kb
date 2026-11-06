"""Track A / A3 — QC auto-loop GATE (cheap hard-threshold filter BEFORE expensive verify).

Per the execution plan (docs/20260925_PEPTIDE_EXECUTION_PLAN.md, item A3): reject candidates
failing hard thresholds (permeability floor, SA ceiling, validity/clash) *before* paying for the
expensive physics verify (MM-GBSA / FEP on AWS). The moat rationale is the QC auto-loop pattern:
run the CHEAP filters first, only spend the expensive oracle on survivors, and log the cost saved.

    gate_candidates(pool, thresholds=GateThresholds()) -> GateResult

Where this sits in the loop
---------------------------
    generate -> [A3 gate]  -> A1 verify (expensive)  -> A2 select -> A4 learn
                 ^^^^^^^^      only survivors reach here

How A3 stays cheap (composes with A1's ``only=`` subset)
--------------------------------------------------------
peptide_verify.verify_peptide accepts ``only=[...]`` to score just a subset of fields. The gate
uses that to compute ONLY the cheap, LOCAL-CPU fields it needs for its thresholds
(``permeability``, ``synthetic_accessibility``, and a structural ``validity`` check) — it never
asks verify for ``affinity_dG`` (which would ingest / imply the AWS physics job). So the gate is
one cheap verify pass; the survivors then get a FULL verify pass (all fields, incl. physics) in A1.

Fail-safe (the plan's honesty requirement)
------------------------------------------
An UNAVAILABLE field (verify degraded a scorer to ``None``) is NOT an automatic reject. A missing
permeability prediction means "we don't know yet," not "it failed the floor." Policy is
configurable per field via ``on_missing`` ("pass" = give benefit of the doubt, default; "reject" =
conservative). Default is fail-OPEN so a broken local scorer never silently kills the whole batch
before the real oracle ever runs. A hard STRUCTURAL invalidity (RDKit can't build a mol at all) is
the one field that defaults to reject, because an unparseable candidate cannot be verified anyway.

Modality-general note
---------------------
The gate logic is chemistry-agnostic: it reads named property values + a direction and compares to
a threshold. Swapping in a small-molecule scorer (Caco-2 permeability, QED, PAINS count) is a
matter of registering different ``GateRule``s and pointing ``verify_fn`` at the small-molecule
verify service. Nothing here is peptide-specific except the DEFAULT thresholds.

CPU only. Never launches a GPU/AWS job.
"""
from __future__ import annotations

import importlib.util
import logging
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Callable, Dict, List, Optional, Sequence

log = logging.getLogger(__name__)

ROOT = Path(__file__).resolve().parent

# Reuse verify's provenance vocabulary without a hard import dependency at module load.
UNAVAILABLE = "unavailable"


# --------------------------------------------------------------------------------------------
# A single hard-threshold rule on one property field.
# --------------------------------------------------------------------------------------------
@dataclass
class GateRule:
    """One hard threshold. ``direction`` says which side passes.

    direction="min": value must be >= threshold (a FLOOR, e.g. permeability floor).
    direction="max": value must be <= threshold (a CEILING, e.g. SA ceiling).
    on_missing: what to do when the field value is None/unavailable —
        "pass"   -> do not reject on this rule (fail-OPEN, benefit of the doubt) [default]
        "reject" -> reject (conservative; the field is required to pass the gate)
    """
    field: str
    threshold: float
    direction: str = "min"          # "min" (floor) | "max" (ceiling)
    on_missing: str = "pass"        # "pass" (fail-open) | "reject" (conservative)

    def evaluate(self, value: Optional[float]) -> "RuleOutcome":
        if value is None:
            passed = (self.on_missing == "pass")
            return RuleOutcome(
                field=self.field, threshold=self.threshold, direction=self.direction,
                value=None, passed=passed, missing=True,
                reason=("field unavailable — " + ("passed (fail-open)" if passed
                        else "rejected (on_missing=reject)")),
            )
        if self.direction == "min":
            passed = value >= self.threshold
            rel = ">=" if passed else "<"
        else:  # "max"
            passed = value <= self.threshold
            rel = "<=" if passed else ">"
        return RuleOutcome(
            field=self.field, threshold=self.threshold, direction=self.direction,
            value=float(value), passed=passed, missing=False,
            reason=f"{value:.4g} {rel} {self.threshold:.4g}",
        )


@dataclass
class RuleOutcome:
    field: str
    threshold: float
    direction: str
    value: Optional[float]
    passed: bool
    missing: bool
    reason: str

    def to_dict(self) -> dict:
        return asdict(self)


# --------------------------------------------------------------------------------------------
# The configurable threshold set. Defaults are peptide-oriented but every number is overridable.
# --------------------------------------------------------------------------------------------
@dataclass
class GateThresholds:
    """Hard thresholds for the cheap pre-filter. All configurable.

    Defaults (peptide developability, honest ranking-grade):
      * permeability floor: candidates below this log-Papp are unlikely to be developable orals.
        Set intentionally permissive (fail-open on missing) so we don't over-cull before verify.
      * synthetic_accessibility ceiling: SA_Score 1(easy)..10(hard); a very-hard-to-make molecule
        is not worth the physics spend.
      * validity: RDKit must be able to build a mol (structural sanity / no gross clash proxy).
        This is the one rule that rejects on missing (an unparseable candidate can't be verified).
    """
    permeability_floor: float = -7.0          # log Papp floor (very permissive default)
    sa_ceiling: float = 6.5                   # SA_Score ceiling (>6.5 = hard to synthesize)
    require_validity: bool = True             # RDKit-parseable structure required
    permeability_on_missing: str = "pass"     # fail-open by default
    sa_on_missing: str = "pass"               # fail-open by default

    def to_rules(self) -> List[GateRule]:
        rules = [
            GateRule("permeability", self.permeability_floor, direction="min",
                     on_missing=self.permeability_on_missing),
            GateRule("synthetic_accessibility", self.sa_ceiling, direction="max",
                     on_missing=self.sa_on_missing),
        ]
        return rules

    # which cheap verify fields the rules need (drives verify's ``only=`` subset)
    def required_verify_fields(self) -> List[str]:
        return ["permeability", "synthetic_accessibility"]


# --------------------------------------------------------------------------------------------
# Per-candidate + batch results
# --------------------------------------------------------------------------------------------
@dataclass
class CandidateGate:
    identifier: str
    passed: bool
    outcomes: List[RuleOutcome] = field(default_factory=list)
    valid_structure: bool = True
    reasons: List[str] = field(default_factory=list)      # human-readable reject reasons
    seq: Optional[str] = None
    smiles: Optional[str] = None

    def to_dict(self) -> dict:
        d = asdict(self)
        return d


@dataclass
class GateResult:
    """Output of one A3 gate pass over a pool."""
    n_in: int
    passed_ids: List[str]
    rejected_ids: List[str]
    per_candidate: Dict[str, CandidateGate]
    thresholds: dict
    verify_fields_used: List[str]
    # cost accounting: the whole point of A3 is to avoid expensive verify on rejects.
    n_expensive_verify_saved: int         # == number rejected (they skip full A1 physics verify)
    notes: List[str] = field(default_factory=list)

    def survivors(self) -> List[str]:
        return list(self.passed_ids)

    def to_dict(self) -> dict:
        return {
            "n_in": self.n_in,
            "passed_ids": self.passed_ids,
            "rejected_ids": self.rejected_ids,
            "per_candidate": {k: v.to_dict() for k, v in self.per_candidate.items()},
            "thresholds": self.thresholds,
            "verify_fields_used": self.verify_fields_used,
            "n_expensive_verify_saved": self.n_expensive_verify_saved,
            "notes": self.notes,
        }


# --------------------------------------------------------------------------------------------
# verify import (lazy — mirrors the sibling-script loading pattern used across the stack)
# --------------------------------------------------------------------------------------------
def _load_verify_module():
    path = ROOT / "peptide_verify.py"
    spec = importlib.util.spec_from_file_location("peptide_verify", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)  # type: ignore[union-attr]
    return mod


def _default_verify_fn():
    """Build the default cheap-verify callable from peptide_verify. Signature:
        verify_fn(seq, smiles, identifier, only=[...]) -> PeptideProperties-like
    Returned lazily so importing peptide_gate never forces the RDKit/verify import chain unless
    the gate is actually run without an injected verify_fn."""
    verify = _load_verify_module()

    def _fn(seq, smiles, identifier, only):
        return verify.verify_peptide(seq=seq, smiles=smiles, identifier=identifier, only=only)

    return _fn


def _check_validity(seq: Optional[str], smiles: Optional[str]) -> bool:
    """Structural validity = RDKit can build a mol. Cheapest possible sanity/clash proxy.
    Fail-safe: if RDKit itself is unavailable we cannot judge → treat as valid (fail-open),
    since the downstream full verify (and physics) will catch a truly broken structure."""
    try:
        from rdkit import Chem, RDLogger  # type: ignore
        RDLogger.DisableLog("rdApp.*")
    except Exception:  # noqa: BLE001  — RDKit missing → cannot check → fail-open
        return True
    mol = None
    if smiles:
        mol = Chem.MolFromSmiles(smiles)
    if mol is None and seq:
        mol = Chem.MolFromSequence(seq)
    return mol is not None


# --------------------------------------------------------------------------------------------
# Public entry points
# --------------------------------------------------------------------------------------------
def gate_candidate(
    candidate: dict,
    thresholds: GateThresholds = GateThresholds(),
    *,
    verify_fn: Optional[Callable] = None,
    verify_kwargs: Optional[dict] = None,
) -> CandidateGate:
    """Gate ONE candidate with a single cheap verify pass (only= the fields the rules need).

    Parameters
    ----------
    candidate : dict with any of ``seq`` / ``smiles`` / ``identifier``.
    thresholds : GateThresholds (configurable floors/ceilings/policies).
    verify_fn : test/pluggable hook — ``verify_fn(seq, smiles, identifier, only)`` returning a
        PeptideProperties-like object (``.scored_fields()`` -> {name: PropertyValue}). Defaults to
        peptide_verify.verify_peptide with ``only=`` set to the cheap fields.
    verify_kwargs : extra kwargs merged into the default verify call (e.g. perm_csv/stab_csv).

    Fail-safe: never raises for a broken scorer; a candidate whose cheap fields all come back
    unavailable simply relies on the ``on_missing`` policy (default pass = deferred to full verify).
    """
    ident = candidate.get("identifier", "") or ""
    seq = candidate.get("seq")
    smiles = candidate.get("smiles")
    rules = thresholds.to_rules()
    cg = CandidateGate(identifier=ident, passed=True, seq=seq, smiles=smiles)

    # 1) validity / clash proxy first (cheapest, gates before we even score).
    if thresholds.require_validity:
        cg.valid_structure = _check_validity(seq, smiles)
        if not cg.valid_structure:
            cg.passed = False
            cg.reasons.append("invalid structure (RDKit could not build a mol)")
            return cg  # no point scoring an unparseable candidate

    # 2) one cheap verify pass restricted to the fields the rules need.
    only = thresholds.required_verify_fields()
    fn = verify_fn or _default_verify_fn()
    vkw = verify_kwargs or {}
    values: Dict[str, Optional[float]] = {}
    try:
        props = fn(seq=seq, smiles=smiles, identifier=ident, only=only, **vkw) \
            if verify_fn is None else fn(seq, smiles, ident, only)
    except TypeError:
        # tolerate both call styles (kw for default, positional for injected hooks)
        props = fn(seq, smiles, ident, only)
    except Exception as e:  # noqa: BLE001 — fail-safe: verify blew up → treat all cheap fields missing
        cg.reasons.append(f"cheap verify raised ({type(e).__name__}: {e}); rules judged on missing policy")
        props = None

    if props is not None:
        fields = props.scored_fields() if hasattr(props, "scored_fields") else {}
        for name in only:
            pv = fields.get(name) if fields else getattr(props, name, None)
            v = getattr(pv, "value", None)
            values[name] = float(v) if v is not None else None
    else:
        for name in only:
            values[name] = None

    # 3) apply each hard rule.
    for rule in rules:
        outcome = rule.evaluate(values.get(rule.field))
        cg.outcomes.append(outcome)
        if not outcome.passed:
            cg.passed = False
            cg.reasons.append(f"{rule.field}: {outcome.reason}")

    return cg


def gate_candidates(
    pool: Sequence[dict],
    thresholds: GateThresholds = GateThresholds(),
    *,
    verify_fn: Optional[Callable] = None,
    verify_kwargs: Optional[dict] = None,
) -> GateResult:
    """Gate a whole pool. Cheap filters run for every candidate; the EXPENSIVE A1 verify (physics)
    is meant to run downstream ONLY on ``result.survivors()``. ``n_expensive_verify_saved`` records
    how many physics verifications the gate avoided (the cost log the plan asks for).

    Never raises for a degraded/empty pool.
    """
    per: Dict[str, CandidateGate] = {}
    passed_ids: List[str] = []
    rejected_ids: List[str] = []
    for i, cand in enumerate(pool):
        # ensure a stable id even if the generator didn't assign one
        if not cand.get("identifier"):
            cand = {**cand, "identifier": f"cand_{i}"}
        cg = gate_candidate(cand, thresholds, verify_fn=verify_fn, verify_kwargs=verify_kwargs)
        per[cg.identifier] = cg
        (passed_ids if cg.passed else rejected_ids).append(cg.identifier)

    notes: List[str] = []
    if not pool:
        notes.append("empty pool")

    return GateResult(
        n_in=len(pool),
        passed_ids=passed_ids,
        rejected_ids=rejected_ids,
        per_candidate=per,
        thresholds=asdict(thresholds),
        verify_fields_used=thresholds.required_verify_fields(),
        n_expensive_verify_saved=len(rejected_ids),
        notes=notes,
    )


if __name__ == "__main__":
    import argparse
    import json

    ap = argparse.ArgumentParser(description="A3 QC gate — cheap hard-threshold pre-filter.")
    ap.add_argument("--pool-json", type=Path,
                    help="JSON list of {identifier, seq, smiles} candidates")
    ap.add_argument("--permeability-floor", type=float, default=GateThresholds.permeability_floor)
    ap.add_argument("--sa-ceiling", type=float, default=GateThresholds.sa_ceiling)
    ap.add_argument("--out", type=Path)
    args = ap.parse_args()

    pool = json.loads(args.pool_json.read_text()) if args.pool_json else []
    th = GateThresholds(permeability_floor=args.permeability_floor, sa_ceiling=args.sa_ceiling)
    res = gate_candidates(pool, th)
    payload = res.to_dict()
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps(payload, indent=2) + "\n")
    print(json.dumps(payload, indent=2))
