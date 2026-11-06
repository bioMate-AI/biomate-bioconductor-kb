"""Track A / A2 — Multi-objective selection over a VERIFIED peptide pool.

Per the execution plan (docs/20260925_PEPTIDE_EXECUTION_PLAN.md, item A2): given a pool of
generated candidates each already carrying a ``PeptideProperties`` vector from A1's verify layer
(peptide_verify.py), return a Pareto-optimal, diverse shortlist for the next synthesis batch
across affinity × permeability × synthetic-accessibility × safety.

    select_batch(props_pool, n_select=10) -> SelectionResult

Selection method — Pareto-front + hypervolume-improvement (HVI), NOT EHVI
------------------------------------------------------------------------
`drug_discovery/bayesian_optimizer.py` implements *E*HVI — the *Expected* hypervolume improvement
under a per-objective Gaussian-process posterior. That is the right acquisition when you are
choosing which *unmeasured* library compounds to run next and you only have a surrogate's
prediction + variance. **Here the pool is already verified**: each candidate has an OBSERVED
property vector (mean + honest uncertainty) from A1. There is no posterior to take an expectation
over, so the correct, non-fabricating objective is *deterministic* HVI over the observed values,
combined with a diversity penalty for the batch. Taking an "expectation" would mean re-fitting a
GP on the very numbers we already measured — circular, and it would import the whole
`galaxy.ai` package tree (numpy/sklearn GP + SQLite + a `CampaignDataset` feature-matrix API),
which does not import cleanly from research/guangzhou_all_atom/ (it pulls galaxy.ai side-effects).
The plan explicitly allows: "if not cleanly importable, implement a clean Pareto-front +
hypervolume-improvement selection with numpy/scipy only." That is what this module does. The two
load-bearing pieces — the Pareto-dominance mask and the Monte-Carlo HVI estimate — are PORTED
from `BayesianOptimizer._compute_pareto_front` / `_hypervolume_improvement` (attribution inline)
so the loop's selection math stays consistent with the small-molecule engine; the difference is
we feed OBSERVED objectives instead of GP means, and we handle the extra realities of a verified
peptide pool that the small-molecule engine never had to: (a) per-objective DIRECTIONS wired from
the verify semantics, (b) MISSING/UNAVAILABLE fields (verify's fail-safe ``None``), and (c)
sequence/SMILES-based DIVERSITY (the engine assumed a dense fingerprint matrix was always present).

How this composes with peptide_verify (A1 -> A2)
------------------------------------------------
* Input is exactly A1's output: a list of ``PeptideProperties`` (from ``verify_peptide`` /
  ``verify_batch``). ``from_verify(...)`` is a thin adapter so callers can hand this module the
  A1 objects directly. No re-scoring happens here — A2 is pure selection.
* Objective DIRECTIONS match the verify field semantics:
      affinity_dG  -> MINIMIZE  (ΔG, more negative = stronger binding)
      permeability -> MAXIMIZE  (log Papp, higher = more permeable)
      synthetic_accessibility -> MINIMIZE (SA 1 easy .. 10 hard)
      safety       -> MAXIMIZE  (P(stable) developability proxy, higher = better)
* MISSING FIELDS: verify degrades any broken scorer to ``value=None``. A candidate missing a ΔG
  must NOT crash selection and must NOT be silently treated as "worst" (that would bury every
  physics-pending candidate). We degrade gracefully per the ``missing`` policy (default
  ``"impute_worst_observed"`` — see ``_normalize_objectives``); a candidate with NO usable
  objective at all is dropped into ``dropped`` with a reason, never fed to the Pareto math.
* DIVERSITY: greedy batch construction adds a Tanimoto-distance bonus (ECFP4) so the shortlist
  is not near-duplicates. Falls back to a sequence-identity distance when RDKit is unavailable.

numpy required; scipy/RDKit optional (diversity degrades to sequence distance without RDKit).
CPU only — this module never launches a GPU/AWS job.
"""
from __future__ import annotations

import importlib.util
import logging
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple

import numpy as np

log = logging.getLogger(__name__)

ROOT = Path(__file__).resolve().parent

# --------------------------------------------------------------------------------------------
# Objective directions — wired to peptide_verify field semantics (see module docstring).
# "minimize" means smaller raw value is better; "maximize" means larger is better.
# --------------------------------------------------------------------------------------------
OBJECTIVE_DIRECTIONS: Dict[str, str] = {
    "affinity_dG": "minimize",              # ΔG kcal/mol, more negative = stronger
    "permeability": "maximize",             # log Papp, higher = more permeable
    "synthetic_accessibility": "minimize",  # SA 1(easy)..10(hard)
    "safety": "maximize",                   # P(stable) proxy, higher = better
}
DEFAULT_OBJECTIVES: Tuple[str, ...] = tuple(OBJECTIVE_DIRECTIONS.keys())


# --------------------------------------------------------------------------------------------
# Optional RDKit (for fingerprint diversity). Degrade to sequence distance if absent.
# --------------------------------------------------------------------------------------------
try:
    from rdkit import Chem, RDLogger  # type: ignore
    from rdkit.Chem import rdFingerprintGenerator  # type: ignore
    RDLogger.DisableLog("rdApp.*")
    _RDKIT = True
    _FPGEN = rdFingerprintGenerator.GetMorganGenerator(radius=2, fpSize=2048)
except Exception:  # noqa: BLE001
    _RDKIT = False
    _FPGEN = None


# --------------------------------------------------------------------------------------------
# Data containers
# --------------------------------------------------------------------------------------------
@dataclass
class Candidate:
    """One pool member: an id, an optional seq/smiles for diversity, and the raw objective
    values keyed by objective name. ``None`` for a missing/unavailable objective (A1 fail-safe)."""
    identifier: str
    objectives: Dict[str, Optional[float]]
    seq: Optional[str] = None
    smiles: Optional[str] = None
    # provenance per objective, carried through for the report (measured/predicted/proxy/…)
    provenance: Dict[str, str] = field(default_factory=dict)


@dataclass
class SelectionResult:
    """Output of one A2 selection round."""
    objectives: List[str]                    # objective names used, in matrix-column order
    directions: Dict[str, str]               # direction per objective
    selected: List[str]                      # chosen candidate ids, batch order
    pareto_front: List[str]                  # all Pareto-optimal candidate ids (superset of picks)
    hvi: Dict[str, float]                    # candidate id -> hypervolume-improvement score
    acquisition: Dict[str, float]            # candidate id -> combined (HVI + diversity) score used
    diversity_score: float                   # mean pairwise Tanimoto distance within the batch
    diversity_metric: str                    # "tanimoto_ecfp4" | "sequence_identity" | "none"
    n_pool: int                              # candidates entering the objective math
    n_dropped: int                           # candidates with no usable objective
    dropped: Dict[str, str]                  # dropped id -> reason
    missing_policy: str                      # how missing fields were handled
    notes: List[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        from dataclasses import asdict
        return asdict(self)


# --------------------------------------------------------------------------------------------
# Adapter: A1 PeptideProperties -> Candidate  (this is how A2 composes with A1/verify)
# --------------------------------------------------------------------------------------------
def _load_verify_module():
    """Import peptide_verify.py as a sibling script (mirrors verify's own _load_module)."""
    path = ROOT / "peptide_verify.py"
    spec = importlib.util.spec_from_file_location("peptide_verify", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)  # type: ignore[union-attr]
    return mod


def from_verify(props_pool: Sequence[object],
                objectives: Sequence[str] = DEFAULT_OBJECTIVES) -> List[Candidate]:
    """Adapt a pool of A1 ``PeptideProperties`` into ``Candidate`` objects for selection.

    Reads each property's ``.value`` (None if the A1 scorer degraded) and ``.provenance``.
    Duck-typed against peptide_verify.PeptideProperties so callers don't have to import both
    modules; a plain object exposing ``scored_fields()`` / attribute ``PropertyValue``s works.
    """
    out: List[Candidate] = []
    for p in props_pool:
        objs: Dict[str, Optional[float]] = {}
        prov: Dict[str, str] = {}
        # prefer the structured accessor when available
        fields = None
        if hasattr(p, "scored_fields"):
            try:
                fields = p.scored_fields()
            except Exception:  # noqa: BLE001
                fields = None
        for name in objectives:
            pv = fields.get(name) if fields is not None else getattr(p, name, None)
            val = getattr(pv, "value", None)
            objs[name] = float(val) if val is not None else None
            prov[name] = getattr(pv, "provenance", "unavailable")
        out.append(Candidate(
            identifier=getattr(p, "identifier", "") or "",
            objectives=objs,
            seq=getattr(p, "sequence", None),
            smiles=getattr(p, "smiles", None),
            provenance=prov,
        ))
    return out


# --------------------------------------------------------------------------------------------
# Objective normalization (missing-field handling lives here)
# --------------------------------------------------------------------------------------------
def _normalize_objectives(
    candidates: Sequence[Candidate],
    objectives: Sequence[str],
    missing: str,
) -> Tuple[np.ndarray, List[Candidate], Dict[str, str], List[str]]:
    """Build an N×M objective matrix in canonical 'higher = better' orientation, in [0, 1].

    Steps:
      1. Drop objectives for which NO candidate has a value (fully-unavailable column).
      2. Drop candidates that have no usable value on ANY surviving objective (-> ``dropped``).
      3. For each surviving objective, min-max scale the observed values to [0, 1] and flip if the
         direction is 'minimize', so larger is always better (matches the ported Pareto/HVI math).
      4. Fill each candidate's MISSING entries per the ``missing`` policy:
           - "impute_worst_observed" (default): the worst *oriented* observed value on that axis,
             i.e. 0.0 after orientation. Honest: a pending ΔG neither helps nor is fabricated —
             the candidate simply can't earn credit on that axis until measured. It can still be
             Pareto-optimal via the axes it DOES have.
           - "impute_mean": the column mean (neutral); use when missingness is not informative.
           - "skip_objective": drop any objective that has ANY missing value (only compare on
             fully-populated axes). Conservative; can collapse to 0 objectives -> falls back.
    Returns (matrix, kept_candidates, dropped{id->reason}, used_objectives).
    """
    dropped: Dict[str, str] = {}

    # (1) which objectives have at least one observed value across the pool
    usable_objs = [o for o in objectives
                   if any(c.objectives.get(o) is not None for c in candidates)]
    if missing == "skip_objective":
        usable_objs = [o for o in usable_objs
                       if all(c.objectives.get(o) is not None for c in candidates)]
        if not usable_objs:  # too aggressive for this pool -> fall back to worst-imputation
            log.warning("skip_objective removed every objective; falling back to impute_worst_observed")
            return _normalize_objectives(candidates, objectives, "impute_worst_observed")

    if not usable_objs:
        for c in candidates:
            dropped[c.identifier] = "no usable objective values in pool"
        return np.zeros((0, 0)), [], dropped, []

    # (2) drop candidates with nothing usable on the surviving objectives
    kept: List[Candidate] = []
    for c in candidates:
        if any(c.objectives.get(o) is not None for o in usable_objs):
            kept.append(c)
        else:
            dropped[c.identifier] = (
                f"all objectives missing ({', '.join(usable_objs)})")
    if not kept:
        return np.zeros((0, 0)), [], dropped, usable_objs

    # (3) per-objective min-max + orientation, computed over OBSERVED values only
    n, m = len(kept), len(usable_objs)
    mat = np.zeros((n, m), dtype=float)
    for j, obj in enumerate(usable_objs):
        vals = np.array([c.objectives.get(obj) for c in kept], dtype=object)
        observed_mask = np.array([v is not None for v in vals])
        observed = np.array([float(v) for v in vals[observed_mask]], dtype=float)
        lo, hi = float(observed.min()), float(observed.max())
        span = (hi - lo) if hi > lo else 1.0
        direction = OBJECTIVE_DIRECTIONS.get(obj, "maximize")
        col = np.zeros(n, dtype=float)
        for i, v in enumerate(vals):
            if v is None:
                continue
            norm = (float(v) - lo) / span            # 0..1, larger raw
            if direction == "minimize":
                norm = 1.0 - norm                    # flip so larger = better
            col[i] = norm
        # (4) impute the missing entries (already 0.0 == worst-oriented)
        if not observed_mask.all():
            if missing == "impute_mean":
                fill = float(col[observed_mask].mean()) if observed_mask.any() else 0.0
                col[~observed_mask] = fill
            # impute_worst_observed / skip_objective -> leave 0.0 (worst after orientation)
        mat[:, j] = col
    return mat, kept, dropped, usable_objs


# --------------------------------------------------------------------------------------------
# Pareto front — PORTED from BayesianOptimizer._compute_pareto_front
# (drug_discovery/bayesian_optimizer.py). Assumes all columns oriented 'higher = better'.
# --------------------------------------------------------------------------------------------
def compute_pareto_front(scores: np.ndarray) -> np.ndarray:
    """Boolean mask of Pareto-dominant rows. Row i is dominated iff some row j is >= on every
    objective and > on at least one."""
    n = scores.shape[0]
    is_pareto = np.ones(n, dtype=bool)
    for i in range(n):
        if not is_pareto[i]:
            continue
        for j in range(n):
            if i == j or not is_pareto[j]:
                continue
            if np.all(scores[j] >= scores[i]) and np.any(scores[j] > scores[i]):
                is_pareto[i] = False
                break
    return is_pareto


# --------------------------------------------------------------------------------------------
# Hypervolume improvement (Monte-Carlo) — PORTED from
# BayesianOptimizer._hypervolume_improvement. Deterministic here: fed OBSERVED objectives, not
# GP means (that is the EHVI-vs-HVI distinction spelled out in the module docstring).
# --------------------------------------------------------------------------------------------
def hypervolume_improvement(
    candidate_scores: np.ndarray,
    pareto_front: np.ndarray,
    reference_point: np.ndarray,
    n_samples: int = 2000,
    rng: Optional[np.random.RandomState] = None,
) -> np.ndarray:
    """MC estimate of the hypervolume each candidate would add to the current front, in [0, 1].
    Samples uniformly in [reference_point, 1]^M and measures the fraction NEWLY dominated when
    the candidate is added."""
    if rng is None:
        rng = np.random.RandomState(0)  # deterministic selection by default
    n_obj = candidate_scores.shape[1]
    upper = np.ones(n_obj)
    if np.all(reference_point >= upper):
        return np.zeros(len(candidate_scores))

    mc = rng.uniform(low=reference_point, high=upper, size=(n_samples, n_obj))
    dominated_by_front = np.zeros(n_samples, dtype=bool)
    for pf in pareto_front:
        dominated_by_front |= np.all(mc <= pf, axis=1)

    hvi = np.zeros(len(candidate_scores))
    for i, cand in enumerate(candidate_scores):
        dom = np.all(mc <= cand, axis=1)
        hvi[i] = (dom & ~dominated_by_front).sum() / n_samples
    return hvi


# --------------------------------------------------------------------------------------------
# Diversity — Tanimoto over ECFP4 (RDKit) with a sequence-identity fallback.
# --------------------------------------------------------------------------------------------
def _fingerprint(cand: Candidate) -> Optional[np.ndarray]:
    if not _RDKIT:
        return None
    mol = None
    if cand.smiles:
        mol = Chem.MolFromSmiles(cand.smiles)
    if mol is None and cand.seq:
        mol = Chem.MolFromSequence(cand.seq)
    if mol is None:
        return None
    return np.asarray(_FPGEN.GetFingerprint(mol), dtype=np.float32)


def _tanimoto_distance(a: np.ndarray, b: np.ndarray) -> float:
    aa, bb = a.astype(bool), b.astype(bool)
    inter = np.logical_and(aa, bb).sum()
    union = np.logical_or(aa, bb).sum()
    return 1.0 - float(inter) / float(union) if union else 0.0


def _sequence_distance(a: Candidate, b: Candidate) -> float:
    """Fallback diversity when no fingerprint: 1 - normalized identity over aligned prefix.
    Crude but monotone — enough to break near-duplicate sequences apart in the greedy step."""
    sa, sb = (a.seq or a.smiles or a.identifier), (b.seq or b.smiles or b.identifier)
    if not sa or not sb:
        return 1.0
    L = max(len(sa), len(sb))
    same = sum(1 for x, y in zip(sa, sb) if x == y)
    return 1.0 - same / L


# --------------------------------------------------------------------------------------------
# Public entry point
# --------------------------------------------------------------------------------------------
def select_batch(
    props_pool: Sequence[object],
    n_select: int = 10,
    *,
    objectives: Sequence[str] = DEFAULT_OBJECTIVES,
    diversity_weight: float = 0.25,
    missing: str = "impute_worst_observed",
    hvi_samples: int = 2000,
    seed: int = 0,
    _candidates: Optional[Sequence[Candidate]] = None,
) -> SelectionResult:
    """Select a Pareto-optimal, diverse shortlist from a verified pool.

    Parameters
    ----------
    props_pool : list of A1 ``PeptideProperties`` (from peptide_verify). Adapted via ``from_verify``.
    n_select : batch size to return.
    objectives : which objectives to optimize (default: all four verify fields).
    diversity_weight : [0,1] weight on the Tanimoto-diversity bonus in greedy batch construction.
    missing : missing-field policy — "impute_worst_observed" | "impute_mean" | "skip_objective".
    hvi_samples : Monte-Carlo samples for the HVI estimate.
    seed : RNG seed (selection is deterministic given the pool).
    _candidates : test hook — pass pre-built ``Candidate`` objects, skipping the verify adapter.

    Returns
    -------
    SelectionResult (never raises for a degraded/empty pool; returns an empty selection with the
    reason in ``notes`` / ``dropped``).
    """
    notes: List[str] = []
    candidates = list(_candidates) if _candidates is not None else from_verify(props_pool, objectives)

    if not candidates:
        return SelectionResult(
            objectives=list(objectives), directions={o: OBJECTIVE_DIRECTIONS.get(o, "maximize")
                                                     for o in objectives},
            selected=[], pareto_front=[], hvi={}, acquisition={}, diversity_score=1.0,
            diversity_metric="none", n_pool=0, n_dropped=0, dropped={},
            missing_policy=missing, notes=["empty pool"])

    mat, kept, dropped, used_objs = _normalize_objectives(candidates, objectives, missing)
    directions = {o: OBJECTIVE_DIRECTIONS.get(o, "maximize") for o in used_objs}

    if used_objs != list(objectives):
        missing_cols = [o for o in objectives if o not in used_objs]
        if missing_cols:
            notes.append(f"objectives dropped (no data / skip policy): {missing_cols}")
    if dropped:
        notes.append(f"{len(dropped)} candidate(s) dropped (no usable objective)")

    if len(kept) == 0 or mat.shape[1] == 0:
        return SelectionResult(
            objectives=used_objs, directions=directions, selected=[], pareto_front=[],
            hvi={}, acquisition={}, diversity_score=1.0, diversity_metric="none",
            n_pool=0, n_dropped=len(dropped), dropped=dropped, missing_policy=missing,
            notes=notes + ["no candidate had a usable objective"])

    ids = [c.identifier for c in kept]

    # Pareto front over the observed, oriented objectives.
    pareto_mask = compute_pareto_front(mat)
    pareto_ids = [ids[i] for i, f in enumerate(pareto_mask) if f]

    # Reference (nadir) point: observed worst per objective minus epsilon — same rationale as the
    # small-molecule engine (a flat-zero reference starves HVI of gradient when all scores sit
    # above the origin). All values are already in [0,1], oriented.
    eps = 1e-3
    reference_point = np.clip(mat.min(axis=0) - eps, 0.0, 1.0)
    rng = np.random.RandomState(seed)
    front_scores = mat[pareto_mask]
    hvi_vals = hypervolume_improvement(mat, front_scores, reference_point,
                                       n_samples=hvi_samples, rng=rng)
    hvi_map = {ids[i]: float(hvi_vals[i]) for i in range(len(ids))}

    # Precompute diversity representations.
    fps = [_fingerprint(c) for c in kept]
    have_fp = _RDKIT and all(f is not None for f in fps)
    diversity_metric = "tanimoto_ecfp4" if have_fp else (
        "sequence_identity" if any((c.seq or c.smiles) for c in kept) else "none")

    def pair_distance(i: int, j: int) -> float:
        if have_fp:
            return _tanimoto_distance(fps[i], fps[j])  # type: ignore[arg-type]
        return _sequence_distance(kept[i], kept[j])

    # Greedy batch construction: (1-w)*HVI + w*min-distance-to-already-selected.
    # PORTED selection loop from BayesianOptimizer.propose_next_round, with the pluggable distance.
    k = min(n_select, len(kept))
    selected_idx: List[int] = []
    acquisition: Dict[str, float] = {}
    remaining = list(range(len(kept)))
    for _ in range(k):
        if not remaining:
            break
        best_i, best_score = None, -np.inf
        for idx in remaining:
            div = (min(pair_distance(idx, s) for s in selected_idx)
                   if selected_idx else 1.0)
            combined = (1.0 - diversity_weight) * hvi_vals[idx] + diversity_weight * div
            if combined > best_score:
                best_score, best_i = combined, idx
        selected_idx.append(best_i)
        acquisition[ids[best_i]] = float(best_score)
        remaining.remove(best_i)

    selected_ids = [ids[i] for i in selected_idx]

    # Batch diversity = mean pairwise distance among selected.
    if len(selected_idx) >= 2:
        pd = [pair_distance(a, b)
              for x, a in enumerate(selected_idx)
              for b in selected_idx[x + 1:]]
        diversity_score = float(np.mean(pd)) if pd else 1.0
    else:
        diversity_score = 1.0

    if diversity_metric == "none":
        notes.append("no seq/smiles for diversity — batch chosen on HVI alone")

    return SelectionResult(
        objectives=used_objs,
        directions=directions,
        selected=selected_ids,
        pareto_front=pareto_ids,
        hvi=hvi_map,
        acquisition=acquisition,
        diversity_score=diversity_score,
        diversity_metric=diversity_metric,
        n_pool=len(kept),
        n_dropped=len(dropped),
        dropped=dropped,
        missing_policy=missing,
        notes=notes,
    )


if __name__ == "__main__":
    import argparse
    import json

    ap = argparse.ArgumentParser(description="A2 multi-objective peptide selection (Pareto+HVI).")
    ap.add_argument("--verify-json", type=Path,
                    help="JSON: list of PeptideProperties.to_dict() from A1 (or verify_batch dump)")
    ap.add_argument("--n-select", type=int, default=10)
    ap.add_argument("--diversity-weight", type=float, default=0.25)
    ap.add_argument("--missing", default="impute_worst_observed",
                    choices=["impute_worst_observed", "impute_mean", "skip_objective"])
    ap.add_argument("--out", type=Path)
    args = ap.parse_args()

    # Reconstruct Candidate objects straight from A1's to_dict() dumps (no re-scoring).
    cands: List[Candidate] = []
    if args.verify_json:
        raw = json.loads(Path(args.verify_json).read_text())
        for rec in raw:
            objs, prov = {}, {}
            for name in DEFAULT_OBJECTIVES:
                pv = rec.get(name) or {}
                objs[name] = pv.get("value")
                prov[name] = pv.get("provenance", "unavailable")
            cands.append(Candidate(identifier=rec.get("identifier", ""), objectives=objs,
                                   seq=rec.get("sequence"), smiles=rec.get("smiles"),
                                   provenance=prov))
    res = select_batch([], n_select=args.n_select, diversity_weight=args.diversity_weight,
                       missing=args.missing, _candidates=cands)
    payload = res.to_dict()
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps(payload, indent=2) + "\n")
    print(json.dumps(payload, indent=2))
