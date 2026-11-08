#!/usr/bin/env python3
"""stage3_provenance.py — FIX #3: conformer provenance tag on every structure.

STATUS: CPU-only (no GPU). The provenance tag is assigned at INGEST (sources.py) from what each
source actually is — that is the correct place, because provenance is a property of the source, not
something to infer after the fact. This stage therefore:
  1. VALIDATES that every record carries a legal provenance tag (schema.CONFORMER_PROVENANCE),
     failing loudly if any source loader forgot one (a guard, not a silent default).
  2. Cross-checks the has_structure flag against the tag (tag!='none' <=> has a real/attached geometry).
  3. Tallies the corpus by provenance so the model lane can enforce "never train a bound-geometry head
     on an xTB/ETKDG conformer" — the stratification table lives in the report.

It deliberately does NOT overwrite tags: if a record's structure gets generated later (ETKDG /
HighFold3 in the D2 lane), the generating step sets the tag, and re-running this stage re-validates.
"""
from __future__ import annotations

from typing import Any, Dict, List

import schema


def run(records: List[Dict[str, Any]]) -> Dict[str, Any]:
    by_tag: Dict[str, int] = {p: 0 for p in schema.CONFORMER_PROVENANCE}
    illegal: List[str] = []
    struct_mismatch: List[str] = []
    for rec in records:
        tag = rec.get("conformer_provenance")
        if tag not in schema.PROVENANCE_RANK:
            illegal.append(f"{schema.record_uid(rec)}:{tag}")
            continue
        by_tag[tag] += 1
        expect_struct = tag != "none"
        if bool(rec.get("has_structure")) != expect_struct:
            # reconcile: has_structure must equal (tag != 'none')
            rec["has_structure"] = expect_struct
            struct_mismatch.append(schema.record_uid(rec))
    if illegal:
        raise ValueError(f"stage3: {len(illegal)} records have an illegal conformer_provenance tag "
                         f"(a source loader forgot fix #3): {illegal[:10]}")
    return {
        "records": len(records),
        "by_provenance": by_tag,
        "experimental_structures": by_tag["PDB_experimental"] + by_tag["NMR_experimental"],
        "computed_structures": by_tag["xTB_CREMP"] + by_tag["HighFold3"] + by_tag["ETKDG"],
        "smiles_only": by_tag["none"],
        "has_structure_reconciled": len(struct_mismatch),
    }
