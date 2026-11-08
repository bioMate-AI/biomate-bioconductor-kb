#!/usr/bin/env python3
"""schema.py — the single ONE schema every source is normalized into for cyclic_corpus_v1.

STATUS: CPU-only data-engineering (no GPU, no training). This is the shared contract the D0
pipeline (`build_cyclic_corpus_v1.py` + stage1..stage4) writes and the model lane (M0/M1/M2)
reads. Keeping it in one place means every source (CycPeptMPDB, CREMP, PepBDB/PepBench,
BindingDB-peptide, approved cyclic drugs, ...) lands in an identical record shape, so the
priority-merge dedup (stage2) and the cyclic-aware split (stage4) never have to special-case a
source.

DESIGN NOTES
------------
* SMILES is the join key of last resort; the real dedup key is the *standardized* canonical
  SMILES computed in stage2 (`std_smiles`), which normalizes tautomers/protonation and
  preserves stereochemistry (stereoisomers of a macrocycle are genuinely different molecules).
* Every structure carries a `ConformerProvenance` tag (fix #3). Losses are stratified by it in
  the model lane; a *bound-geometry* head must never be trained on an xTB/ETKDG conformer.
* `labels` is a dict keyed by assay so priority-merge can UNION labels across duplicate rows
  from different sources (fix #2: "merge labels").
* `split` is assigned by stage4 AFTER the eval set is frozen. `eval_frozen` / `premium_eval`
  flag the two held-out tiers the leakage gate protects (the standard CREMP benchmark split and
  the ~3,258 CREMP measured-permeability premium eval).
"""
from __future__ import annotations

import hashlib
import json
from typing import Any, Dict, List, Optional


# ---- Fix #3: conformer provenance (single source of truth) -----------------------------------
# Ordered best -> worst for the priority-merge in stage2 (experimental structure beats computed).
CONFORMER_PROVENANCE = [
    "PDB_experimental",   # crystallographic / cryo-EM coordinates from the PDB (best)
    "NMR_experimental",   # solution-NMR ensemble (experimental, solution-phase)
    "xTB_CREMP",          # CREMP semi-empirical (GFN2-xTB) conformer ensemble (computed, solution)
    "HighFold3",          # HighFold3 / HighFold-MeD predicted cyclic pose (computed)
    "ETKDG",              # RDKit ETKDG distance-geometry embedding (computed, cheapest)
    "none",               # SMILES-only, no 3D structure attached
]
PROVENANCE_RANK = {p: i for i, p in enumerate(CONFORMER_PROVENANCE)}

# Fix #2: exact-match keep order for the priority-merge dedup. Higher = kept as the canonical row
# (experimental crystal > NMR > xTB-CREMP > ETKDG-generated). Independent of conformer provenance so
# a SMILES-only row from an experimental source is still ranked by where its *label* came from.
SOURCE_TIER = {
    "PDB_experimental": 5,
    "NMR_experimental": 4,
    "xTB_CREMP": 3,
    "HighFold3": 2,
    "ETKDG": 1,
    "none": 0,
}


def new_record(
    source: str,
    smiles: str,
    *,
    helm: Optional[str] = None,
    helm_canonical: Optional[str] = None,
    sequence: Optional[List[str]] = None,
    residues: Optional[List[Dict[str, Any]]] = None,
    conformer_provenance: str = "none",
    source_tier: Optional[str] = None,
    labels: Optional[Dict[str, Any]] = None,
    source_id: Optional[str] = None,
    is_cyclic: Optional[bool] = None,
    n_nme: int = 0,
    n_daa: int = 0,
    all_supported: Optional[bool] = None,
    extra: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    """Build one corpus record in the canonical schema. `conformer_provenance` must be one of
    CONFORMER_PROVENANCE. `source_tier` (for the dedup priority) defaults to the provenance tag
    when not given explicitly (i.e. an experimental structure implies an experimental source)."""
    assert conformer_provenance in PROVENANCE_RANK, f"bad provenance {conformer_provenance!r}"
    st = source_tier or conformer_provenance
    assert st in SOURCE_TIER, f"bad source_tier {st!r}"
    return {
        # identity / origin
        "source": source,                       # e.g. "CycPeptMPDB", "CREMP", "PepBDB"
        "source_id": source_id,                 # native id in that source
        # chemistry
        "smiles": (smiles or "").strip(),
        "std_smiles": None,                     # filled by stage2 (standardized canonical SMILES)
        "inchikey": None,                       # filled by stage2 (stereo-sensitive)
        "inchikey_skeleton": None,              # filled by stage2 (connectivity-only, for audit)
        "helm": helm,
        "helm_canonical": helm_canonical,       # filled/overwritten by stage1
        "sequence": sequence or [],             # list of monomer tokens
        "residues": residues or [],             # per-residue dicts (parent/nme/d_amino/raw), if parsed
        # modifications
        "n_nme": int(n_nme),
        "n_daa": int(n_daa),
        "all_supported": all_supported,         # every monomer maps to a canonical parent (+N-Me/+D)
        # geometry provenance (fix #3)
        "conformer_provenance": conformer_provenance,
        "source_tier": st,                      # dedup priority tag (fix #2)
        "has_structure": conformer_provenance != "none",
        # labels (fix #2 merge): {assay_name: {"value":..., "unit":..., "source":...}}
        "labels": labels or {},
        # cyclicity
        "is_cyclic": is_cyclic,
        # split (fix #4) — assigned by stage4 AFTER freeze
        "split": None,                          # "train" | "val" | "test"
        "eval_frozen": False,                   # in the frozen held-out benchmark eval set
        "premium_eval": False,                  # CREMP measured-permeability premium eval tier
        "cluster_id": None,                     # sequence/Tanimoto cluster the split respects
        # free-form carry-through
        "extra": extra or {},
    }


def record_uid(rec: Dict[str, Any]) -> str:
    """Stable per-record uid = source + source_id (or a hash of raw SMILES if no id)."""
    sid = rec.get("source_id")
    if sid is None or str(sid).strip() == "":
        sid = hashlib.sha1((rec.get("smiles") or "").encode()).hexdigest()[:12]
    return f"{rec['source']}:{sid}"


def dump_jsonl(records: List[Dict[str, Any]], path) -> int:
    n = 0
    with open(path, "w") as f:
        for r in records:
            f.write(json.dumps(r) + "\n")
            n += 1
    return n


def load_jsonl(path) -> List[Dict[str, Any]]:
    out = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line:
                out.append(json.loads(line))
    return out
