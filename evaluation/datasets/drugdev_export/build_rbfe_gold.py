#!/usr/bin/env python3
"""Build the N1 rbfe_benchmark gold from the public Merck/Schindler FEP benchmark.

Source: github.com/MCompChem/fep-benchmark (MIT, Schindler et al., JCIM 2020, 60:5457) —
8 pharma congeneric series with EXPERIMENTAL per-ligand binding free energies. We derive
each series' relative ΔΔG = Exp.ΔG(ligand) − Exp.ΔG(reference_ligand). These are REAL
experimental values (nothing invented); the reference ligand is the first ligand listed
per series (deterministic).

Obtain the source (not vendored here) then run:
    git clone --depth 1 https://github.com/MCompChem/fep-benchmark.git ~/fep-benchmark-dig
    FEP_BENCHMARK_DIR=~/fep-benchmark-dig python3 evaluation/datasets/drugdev_export/build_rbfe_gold.py

Writes rbfe_benchmark/data.jsonl (one series per target). Ligand STRUCTURES are not
embedded — they live in each target's public `ligands.sdf` (referenced via `source`);
the benchmark grades the agent's FEP run output vs the `reference` ΔΔG.
"""
import csv
import glob
import json
import os
from pathlib import Path

HERE = Path(__file__).resolve().parent
SRC = Path(os.environ.get("FEP_BENCHMARK_DIR", os.path.expanduser("~/fep-benchmark-dig")))
TARGETS = ["cdk8", "cmet", "eg5", "hif2a", "pfkfb3", "shp2", "syk", "tnks2"]


def _exp_dg_col(fieldnames):
    for f in fieldnames:
        k = f.strip().lower()
        if k.startswith("exp") and "error" not in k:  # "Exp. ΔG"
            return f
    raise KeyError("no experimental ΔG column in " + str(fieldnames))


def _ligand_col(fieldnames):
    for f in fieldnames:
        if f.strip().lower() == "ligand":
            return f
    raise KeyError("no Ligand column")


def build_series(target):
    d = SRC / target
    csv_path = d / "results_20ns.csv"
    if not csv_path.is_file():
        return None
    with csv_path.open() as f:
        reader = csv.DictReader(f)
        rows = [r for r in reader if r.get(_ligand_col(reader.fieldnames), "").strip()]
        lig_col, dg_col = _ligand_col(reader.fieldnames), _exp_dg_col(reader.fieldnames)
    pairs = []
    for r in rows:
        lig = str(r[lig_col]).strip()
        try:
            dg = float(r[dg_col])
        except (TypeError, ValueError):
            continue
        pairs.append((lig, dg))
    if len(pairs) < 3:
        return None
    ref_lig, ref_dg = pairs[0]
    reference = {lig: round(dg - ref_dg, 3) for lig, dg in pairs}
    pdb = next((Path(p).stem for p in glob.glob(str(d / "*.pdb"))), None)
    return {
        "id": f"RBFE-{target}",
        "target": target.upper(),
        "pdb": pdb,
        "source": f"MCompChem/fep-benchmark/{target} (ligands.sdf)",
        "reference_ligand": ref_lig,
        "n_ligands": len(pairs),
        "affinity_unit": "kcal/mol",
        "reference": reference,
        "difficulty": "hard",
    }


def main():
    if not SRC.is_dir():
        raise SystemExit(f"FEP source not found: {SRC}\n  git clone --depth 1 "
                         "https://github.com/MCompChem/fep-benchmark.git " + str(SRC))
    items = [s for t in TARGETS if (s := build_series(t))]
    out = HERE / "rbfe_benchmark" / "data.jsonl"
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("w") as f:
        for it in items:
            f.write(json.dumps(it) + "\n")
    total = sum(it["n_ligands"] for it in items)
    print(f"rbfe_benchmark: {len(items)} series, {total} ligands -> {out}")
    for it in items:
        print(f"  {it['id']}: {it['n_ligands']} ligands (ref {it['reference_ligand']})")


if __name__ == "__main__":
    main()
