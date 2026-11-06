#!/usr/bin/env python3
"""stage2_standardize_dedup.py — FIX #2: SMILES standardization + priority-merge dedup.

STATUS: CPU-only RDKit (no GPU). Two jobs:

  (A) STANDARDIZE every record's SMILES with RDKit MolStandardize:
        normalize (functional-group canonicalization) -> uncharge (neutralize protonation states)
        -> canonical tautomer (bounded; skipped for very large macrocycles where it is too slow)
        -> canonical SMILES (stereo PRESERVED).
      Writes rec['std_smiles'], rec['inchikey'] (stereo-sensitive) and rec['inchikey_skeleton']
      (connectivity-only, for audit). A macrocycle ring-membership check sets rec['is_cyclic'] when
      the source left it None (BindingDB etc.).

  (B) PRIORITY-MERGE DEDUP on the standardized key. Exact-match keep order (fix #2):
        experimental crystal (PDB) > NMR > xTB-CREMP > ETKDG-generated  (via schema.SOURCE_TIER).
      When two+ records share a std key, ONE canonical record is kept (highest source_tier; ties
      broken by "has a real structure" then by more labels), and the OTHERS' labels are MERGED into
      it (union across assays) so no measurement is lost. The dropped uids are recorded.

WHY SMILES-ONLY EXACT-MATCH IS INSUFFICIENT (the doc's point): tautomers, undefined stereo and
protonation cause false NEGATIVES (same molecule, different string) — standardization first is what
makes the dedup honest. We dedup on the *stereo-sensitive* standardized InChIKey so genuine
stereoisomers stay distinct; the connectivity skeleton is reported only for audit (it over-merges).
"""
from __future__ import annotations

import sys
from typing import Any, Dict, List, Optional, Tuple

import schema


def _get_rdkit():
    from rdkit import Chem, RDLogger
    from rdkit.Chem import inchi
    from rdkit.Chem.MolStandardize import rdMolStandardize
    RDLogger.DisableLog("rdApp.*")
    return Chem, inchi, rdMolStandardize


# tautomer canonicalization is O(2^tautomerizable-sites); cap heavy atoms to keep the ETL bounded.
_TAUTOMER_MAX_HEAVY = 70


def standardize_smiles(smiles: str, rd, do_tautomer: bool = True):
    """Return (std_canonical_smiles, inchikey, inchikey_skeleton, is_cyclic, n_macrocycle_atoms) or Nones."""
    Chem, inchi, rdMolStandardize = rd
    m = Chem.MolFromSmiles(smiles)
    if m is None:
        return None, None, None, None, 0
    try:
        m = rdMolStandardize.Normalizer().normalize(m)
        m = rdMolStandardize.Uncharger().uncharge(m)
        if do_tautomer and m.GetNumHeavyAtoms() <= _TAUTOMER_MAX_HEAVY:
            m = rdMolStandardize.TautomerEnumerator().Canonicalize(m)
    except Exception:
        # standardization can throw on exotic valences; fall back to the parsed (un-standardized) mol
        m = Chem.MolFromSmiles(smiles)
        if m is None:
            return None, None, None, None, 0
    std = Chem.MolToSmiles(m)
    try:
        ik = inchi.MolToInchiKey(m)
    except Exception:
        ik = None
    skel = ik.split("-")[0] if ik else None
    # macrocycle detection: a ring with >= 8 atoms (backbone macrolactam) => cyclic peptide
    ri = m.GetRingInfo()
    max_ring = max((len(r) for r in ri.AtomRings()), default=0)
    is_cyclic = max_ring >= 8
    return std, ik, skel, is_cyclic, max_ring


def run(records: List[Dict[str, Any]], do_tautomer: bool = True,
        dedup_key: str = "inchikey") -> Tuple[List[Dict[str, Any]], Dict[str, Any]]:
    """Standardize + dedup. dedup_key='inchikey' (stereo-sensitive, recommended) or 'std_smiles'.
    Returns (deduped_records, stats)."""
    try:
        rd = _get_rdkit()
    except Exception as e:
        raise RuntimeError(f"stage2 requires RDKit with MolStandardize: {e}")

    n_parse_fail = 0
    for i, rec in enumerate(records):
        if i and i % 2000 == 0:
            print(f"[stage2] standardized {i}/{len(records)}", file=sys.stderr, flush=True)
        std, ik, skel, is_cyc, max_ring = standardize_smiles(rec["smiles"], rd, do_tautomer=do_tautomer)
        rec["std_smiles"] = std
        rec["inchikey"] = ik
        rec["inchikey_skeleton"] = skel
        rec["max_ring_size"] = max_ring
        if std is None:
            n_parse_fail += 1
        if rec.get("is_cyclic") is None:
            rec["is_cyclic"] = is_cyc

    # ---- priority-merge dedup ----
    def key_of(r):
        if dedup_key == "std_smiles":
            return r.get("std_smiles")
        return r.get("inchikey")

    def rank(r):
        # higher tuple sorts as "keep": source_tier, has_structure, #labels
        return (schema.SOURCE_TIER.get(r.get("source_tier", "none"), 0),
                1 if r.get("has_structure") else 0,
                len(r.get("labels") or {}))

    groups: Dict[Any, List[Dict[str, Any]]] = {}
    no_key = []
    for r in records:
        k = key_of(r)
        if k is None:
            no_key.append(r)
        else:
            groups.setdefault(k, []).append(r)

    deduped: List[Dict[str, Any]] = []
    dropped_uids: List[str] = []
    n_merged_labels = 0
    for k, grp in groups.items():
        grp_sorted = sorted(grp, key=rank, reverse=True)
        keep = grp_sorted[0]
        for other in grp_sorted[1:]:
            # union labels (fix #2 "merge labels") — don't overwrite an existing assay
            for assay, val in (other.get("labels") or {}).items():
                if assay not in keep["labels"]:
                    keep["labels"][assay] = val
                    n_merged_labels += 1
            dropped_uids.append(schema.record_uid(other))
        # record the merge provenance
        keep.setdefault("extra", {})["merged_from"] = [schema.record_uid(o) for o in grp_sorted[1:]]
        keep["extra"]["dup_sources"] = sorted({o["source"] for o in grp})
        deduped.append(keep)
    # rows with no standardized key (parse failures) are kept but flagged — never silently dropped
    for r in no_key:
        r.setdefault("extra", {})["std_key_missing"] = True
        deduped.append(r)

    stats = {
        "input_records": len(records),
        "parse_failures": n_parse_fail,
        "dedup_key": dedup_key,
        "unique_after_dedup": len(deduped),
        "duplicates_removed": len(dropped_uids),
        "labels_merged": n_merged_labels,
        "records_no_std_key_kept": len(no_key),
        "unique_inchikey_skeleton_audit": len({r.get("inchikey_skeleton") for r in records
                                               if r.get("inchikey_skeleton")}),
    }
    return deduped, stats
