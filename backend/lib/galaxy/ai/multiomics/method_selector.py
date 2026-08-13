"""Flexible multi-omics integration — data-shape-driven method selection.

Given an arbitrary set of omics modality descriptors, decide HOW to integrate them:
inspect the data shape (how many modalities, fully-paired vs partial-overlap/mosaic
samples, single-cell present, data-type mix, dimensionality) and recommend the
appropriate integration method from BioMate's catalog, plus the per-modality
normalization plan and the aligned sample set.

This is the "flexible integration" intelligence layer — the multi-omics counterpart
of workflow routing. The user brings whatever omics they have and BioMate picks the
right integrator, instead of being hard-wired to one method (the current
bioconductor_multiomics workflow is hardcoded to MOFA2 with rna+protein only).

Pure stdlib — operates on descriptors + sample-id sets. No numpy/pandas.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Union

# --- data-type taxonomy -----------------------------------------------------
SINGLE_CELL = {"scrna", "scatac", "spatial"}
# non-negative matrices (eligible for integrative NMF)
NON_NEGATIVE = {"rna", "scrna", "mirna", "scatac", "metabolomics"}
# continuous matrices suitable for factor / co-inertia methods
CONTINUOUS = {"rna", "scrna", "methylation", "scatac", "proteomics",
              "mirna", "metabolomics", "drug_response", "spatial"}
# discrete / categorical blocks
DISCRETE = {"mutation", "cnv"}

# per-modality SOTA normalization (mirrors the omics_normalize workflow)
NORMALIZATION: Dict[str, str] = {
    "rna": "log2-CPM",
    "mirna": "log2-CPM",
    "scrna": "log1p(CP10k)",
    "spatial": "log1p(CP10k)",
    "methylation": "M-value",
    "scatac": "TF-IDF",
    "proteomics": "log2 + median-centre",
    "drug_response": "quantile",
    "metabolomics": "quantile",
    "mutation": "pass-through",
    "cnv": "pass-through",
}
KNOWN_TYPES = set(NORMALIZATION.keys())

# integration-method catalog: name -> one-line description
METHODS: Dict[str, str] = {
    "MOFA2": "latent-factor integration (ARD) — interpretable shared factors across paired continuous omics",
    "SNF": "similarity network fusion — patient clustering / molecular subtypes",
    "MCIA": "multiple co-inertia — robust across high-dimensional, mixed-magnitude blocks",
    "iClusterPlus": "Bayesian joint clustering with integrated feature selection",
    "JIVE": "joint + individual variation explained",
    "MFA": "multi-block factor analysis (base-R SVD — no heavy dependencies)",
    "intNMF": "integrative non-negative matrix factorisation (non-negative data)",
    "StabMap": "mosaic embedding — integrates partially-overlapping / single-cell modalities",
}

# a block with more features than this counts as 'high-dimensional'
HIGH_DIM_THRESHOLD = 10_000


@dataclass
class Modality:
    """One omics layer. Provide `sample_ids` when known so partial-overlap
    (mosaic) data can be detected; otherwise `n_samples` is used and pairing
    is assumed (with a warning)."""
    name: str
    data_type: str
    sample_ids: Optional[List[str]] = None
    n_samples: Optional[int] = None
    n_features: Optional[int] = None

    def dtype(self) -> str:
        return (self.data_type or "").strip().lower()

    def samples(self) -> Optional[set]:
        return set(self.sample_ids) if self.sample_ids else None

    def count(self) -> int:
        if self.sample_ids:
            return len(self.sample_ids)
        return int(self.n_samples or 0)

    def features(self) -> int:
        try:
            return int(self.n_features or 0)
        except (TypeError, ValueError):
            return 0


def _as_modality(m: Union[Modality, Dict[str, Any]]) -> Modality:
    if isinstance(m, Modality):
        return m
    return Modality(
        name=m.get("name"),
        data_type=m.get("data_type"),
        sample_ids=m.get("sample_ids"),
        n_samples=m.get("n_samples"),
        n_features=m.get("n_features"),
    )


def _coerce(modalities: List[Union[Modality, Dict[str, Any]]]) -> List[Modality]:
    return [_as_modality(m) for m in (modalities or [])]


def normalization_for(data_type: str) -> str:
    """SOTA normalization for one modality; 'pass-through' for unknown types."""
    return NORMALIZATION.get((data_type or "").strip().lower(), "pass-through")


def normalization_plan(modalities: List[Union[Modality, Dict[str, Any]]]) -> Dict[str, str]:
    """Per-modality normalization plan: {modality_name: transform}."""
    mods = _coerce(modalities)
    return {m.name: normalization_for(m.dtype()) for m in mods}


def sample_alignment(modalities: List[Union[Modality, Dict[str, Any]]]) -> Dict[str, Any]:
    """Intersect samples across modalities. Returns the shared set and the
    per-modality retained/dropped counts, making partial-overlap explicit.
    Falls back to `n_samples` (assumes paired) when sample_ids are absent."""
    mods = _coerce(modalities)
    sets = [m.samples() for m in mods]

    if mods and all(s is not None for s in sets):
        inter = set.intersection(*sets)
        union = set.union(*sets)
        per = [{
            "name": m.name,
            "n_samples": len(s),
            "retained": len(inter),
            "dropped": len(s) - len(inter),
        } for m, s in zip(mods, sets)]
        if len(inter) == 0:
            overlap = "disjoint"
        elif len(inter) == len(union):
            overlap = "fully_paired"
        else:
            overlap = "partial_overlap"
        return {
            "ids_available": True,
            "overlap_type": overlap,
            "aligned_samples": sorted(inter),
            "n_aligned": len(inter),
            "n_union": len(union),
            "per_modality": per,
        }

    # no sample IDs — use counts, assume paired on the smallest block
    counts = [m.count() for m in mods]
    n = min(counts) if counts else 0
    return {
        "ids_available": False,
        "overlap_type": "assumed_paired",
        "aligned_samples": None,
        "n_aligned": n,
        "n_union": max(counts) if counts else 0,
        "per_modality": [
            {"name": m.name, "n_samples": c, "retained": n, "dropped": max(0, c - n)}
            for m, c in zip(mods, counts)
        ],
    }


def select_method(
    modalities: List[Union[Modality, Dict[str, Any]]],
    goal: Optional[str] = None,
    constraints: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    """Pick the integration method from the data shape + optional goal.

    Returns {recommended_method, method_description, rationale, alternatives, warnings}.
    `recommended_method` is None for the degenerate single-modality case.
    goal ∈ {factors, clustering, subtypes, feature_selection, None};
    constraints e.g. {'no_heavy_deps': True}.
    """
    mods = _coerce(modalities)
    if not mods:
        raise ValueError("no modalities provided — need at least 2 for integration")

    constraints = constraints or {}
    goal = (goal or "").strip().lower() or None
    warnings: List[str] = []

    dtypes = [m.dtype() for m in mods]
    for m, dt in zip(mods, dtypes):
        if dt not in KNOWN_TYPES:
            warnings.append(
                f"unknown data_type '{dt}' for modality '{m.name}' — treated as continuous")

    n_mod = len(mods)
    align = sample_alignment(mods)
    overlap = align["overlap_type"]
    if overlap == "assumed_paired":
        warnings.append("sample_ids not provided — assuming modalities are paired; "
                        "provide sample_ids to detect partial-overlap/mosaic data")
    if overlap == "disjoint":
        warnings.append("modalities share no samples — vertical integration impossible; "
                        "a mosaic method (StabMap) or shared features are required")

    # degenerate: not an integration problem
    if n_mod < 2:
        return {
            "recommended_method": None,
            "method_description": None,
            "rationale": ("only one modality supplied — multi-omics integration needs at "
                          "least two. Run a single-omics workflow for this data instead."),
            "alternatives": [],
            "warnings": warnings + ["single modality: no integration performed"],
        }

    has_single_cell = any(dt in SINGLE_CELL for dt in dtypes)
    all_non_negative = all(dt in NON_NEGATIVE for dt in dtypes)
    max_features = max((m.features() for m in mods), default=0)
    distinct_types = len(set(dtypes))
    high_dim_mixed = (n_mod >= 3 and max_features >= HIGH_DIM_THRESHOLD
                      and distinct_types >= 2)

    mosaic = overlap in ("partial_overlap", "disjoint") or (
        has_single_cell and overlap not in ("fully_paired", "assumed_paired"))

    # --- precedence-ordered selection cascade ---------------------------------
    if mosaic:
        method = "StabMap"
        rationale = ("samples are not fully paired across modalities"
                     + (" and single-cell data is present" if has_single_cell else "")
                     + " — the paired-sample methods would drop the non-shared samples, so "
                       "a mosaic-capable embedding (StabMap) is required.")
        warnings.append("REQUIRES a mosaic-capable method: MOFA2/SNF/MCIA/iClusterPlus/"
                        "JIVE/MFA all assume fully-paired samples.")
        alternatives = ["MOFA+ (mosaic mode)"]
    elif constraints.get("no_heavy_deps"):
        method = "MFA"
        rationale = ("a no-heavy-dependency constraint was set — MFA is a base-R SVD "
                     "multi-block factor method with no compilation requirements.")
        alternatives = ["MOFA2", "MCIA"]
    elif goal == "feature_selection":
        method = "iClusterPlus"
        rationale = ("goal is joint clustering with feature selection — iClusterPlus does "
                     "Bayesian latent-variable clustering with built-in sparsity.")
        alternatives = ["MOFA2", "intNMF"]
    elif goal in ("clustering", "subtypes"):
        method = "SNF"
        rationale = ("goal is patient clustering / molecular subtypes — SNF fuses the "
                     "per-modality similarity networks into one for robust clustering.")
        alternatives = ["iClusterPlus", "intNMF", "MCIA"]
    elif high_dim_mixed:
        method = "MCIA"
        rationale = (f"{n_mod} high-dimensional blocks of mixed data types "
                     f"(up to {max_features:,} features) — MCIA (co-inertia) is the most "
                     f"robust for heterogeneous, differently-scaled blocks (Cantini 2021).")
        alternatives = ["MOFA2", "MFA", "intNMF"]
    elif all_non_negative:
        method = "intNMF"
        rationale = ("all modalities are non-negative (counts/intensities) — integrative "
                     "NMF gives interpretable non-negative factors plus a clustering.")
        alternatives = ["MOFA2", "SNF"]
    else:
        method = "MOFA2"
        rationale = ("paired continuous modalities with an interpretation/factor goal — "
                     "MOFA2 learns shared latent factors (ARD) with variance explained "
                     "per view.")
        alternatives = ["MCIA", "MFA", "SNF"]

    return {
        "recommended_method": method,
        "method_description": METHODS.get(method),
        "rationale": rationale,
        "alternatives": alternatives,
        "warnings": warnings,
    }


def recommend(
    modalities: List[Union[Modality, Dict[str, Any]]],
    goal: Optional[str] = None,
    constraints: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    """Top-level entry: full integration plan for an arbitrary set of omics.

    Returns:
      recommended_method, method_description, rationale, alternatives,
      overlap_type, n_modalities, data_types, single_cell,
      normalization_plan, aligned_samples, warnings
    """
    mods = _coerce(modalities)
    sel = select_method(mods, goal=goal, constraints=constraints)
    align = sample_alignment(mods)
    return {
        "recommended_method": sel["recommended_method"],
        "method_description": sel["method_description"],
        "rationale": sel["rationale"],
        "alternatives": sel["alternatives"],
        "overlap_type": align["overlap_type"],
        "n_modalities": len(mods),
        "data_types": [m.dtype() for m in mods],
        "single_cell": any(m.dtype() in SINGLE_CELL for m in mods),
        "normalization_plan": normalization_plan(mods),
        "aligned_samples": align,
        "warnings": sel["warnings"],
    }


# Back-compat alias for callers expecting the verbose name.
select_integration_method = recommend
