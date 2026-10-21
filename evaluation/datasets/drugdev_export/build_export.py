#!/usr/bin/env python3
"""Build the neutralized public item files for the DrugDev-series benchmarks that are
NOT already published in RealBio (B1 ADMET, B5 target-structure).

B2 docking / B3 pbpk / B4 boin are already public in ../public_export/ (and referenced by
this bundle's per-benchmark READMEs); they are not duplicated here to avoid drift. The
planned net-new benchmarks (N1 rbfe, N8 pipeline_e2e, ...) have no gold yet.

Mirrors ../public_export/build_export.py: a per-benchmark `keep` whitelist (objective
ground truth IS public, matching the RealBio design) and a leak guard. Run:
    python3 evaluation/datasets/drugdev_export/build_export.py
"""
import json
import os

import yaml

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.abspath(os.path.join(HERE, ".."))  # evaluation/datasets

# Internal fields that must never be published (none appear in the B1/B5 gold today; the
# guard is kept so a future field addition fails loudly rather than leaking).
LEAK_FIELDS = {"biomate_profile", "expected_fixer_class", "expected_biomate_action", "notes"}

RULES = {
    "admet_benchmark": dict(
        src="admet_benchmark/cases.yaml", list_key="cases",
        keep=["id", "name", "smiles", "reference", "difficulty"],
        gt="reference",
    ),
    "target_structure_benchmark": dict(
        src="target_structure_benchmark/cases.yaml", list_key="cases",
        keep=["id", "name", "uniprot_id", "fasta", "expected_pocket_residues",
              "expected_druggable", "difficulty"],
        gt=["expected_pocket_residues", "expected_druggable"],
    ),
}


def load_list(path, list_key=None):
    y = yaml.safe_load(open(path))
    if list_key:
        return y[list_key]
    if isinstance(y, list):
        return y
    for v in y.values():
        if isinstance(v, list) and v and isinstance(v[0], dict):
            return v
    raise ValueError(f"no item list in {path}")


def neutralize(item, spec):
    keep = set(spec["keep"])
    ren = spec.get("rename", {})
    out = {}
    for k, v in item.items():
        if k in ren:
            out[ren[k]] = v
        elif k in keep:
            out[k] = v
    return out


def main():
    for name, spec in RULES.items():
        items = load_list(os.path.join(SRC, spec["src"]), spec.get("list_key"))
        rows = [neutralize(it, spec) for it in items]
        leaked = sorted({k for r in rows for k in r} & LEAK_FIELDS)
        assert not leaked, f"{name}: leaked internal fields survived: {leaked}"
        outdir = os.path.join(HERE, name)
        os.makedirs(outdir, exist_ok=True)
        with open(os.path.join(outdir, "data.jsonl"), "w") as f:
            for r in rows:
                f.write(json.dumps(r) + "\n")
        print(f"{name}: {len(rows)} items (gt={spec['gt']}) -> {name}/data.jsonl")


if __name__ == "__main__":
    main()
