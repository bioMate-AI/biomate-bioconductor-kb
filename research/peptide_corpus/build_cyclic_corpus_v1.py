#!/usr/bin/env python3
"""build_cyclic_corpus_v1.py — D0 orchestrator: aggregate cyclic-peptide DBs into ONE schema with the
4 blocking data-quality fixes, then FREEZE the eval set before any training assembly.

STATUS: CPU-only ETL (NO GPU, NO training). This is convergence point ① of the peptide parallel work
plan (docs/20260927_PEPTIDE_PARALLEL_WORK_PLAN.md, D0) and implements Part A's 4 fixes + the
leakage/eval-freeze gate from docs/20260927_CYCLIC_CORPUS_AND_TRAINING_STRATEGY.md.

PIPELINE (each fix = one stage):
  sources.load_all        -> canonical records (schema.new_record); provenance assigned at ingest
  stage1_helm_canon.run   -> FIX #1 HELM2 monomer canonicalization (+ round-trip GATE on 200)
  stage2_standardize_dedup-> FIX #2 RDKit standardization + priority-merge dedup (exp>NMR>xTB>ETKDG)
  stage3_provenance.run   -> FIX #3 validate + tally conformer provenance
  stage4_split.run        -> FIX #4 cyclic-aware split, FREEZE eval first, leakage report

OUTPUT (cyclic_corpus_v1/):
  records.jsonl           -- every deduped record in the ONE schema (with std_smiles, provenance, split)
  eval_frozen.jsonl       -- the frozen held-out eval set (test+val), family-disjoint
  premium_eval.jsonl      -- the CREMP measured-permeability premium eval subset
  train.jsonl             -- training remainder (assembled AFTER the freeze)
  leakage_report.json     -- the train/test similarity table + all 4 gate results
  manifest.json           -- provenance of the build (counts per stage, sources present, deps)

USAGE:
  # local-only smoke (CycPeptMPDB CSV + approved-drugs CSV that are present locally):
  python3 build_cyclic_corpus_v1.py --out cyclic_corpus_v1 --limit 1500

  # full local CycPeptMPDB:
  python3 build_cyclic_corpus_v1.py --out cyclic_corpus_v1

  # with S3 datasets pulled + extracted into a staging dir (CREMP/PepBDB/BindingDB):
  python3 build_cyclic_corpus_v1.py --out cyclic_corpus_v1 --staging /path/to/cyclic_staging
"""
from __future__ import annotations

import argparse
import json
import platform
import sys
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

import schema
import sources
import stage1_helm_canon as s1
import stage2_standardize_dedup as s2
import stage3_provenance as s3
import stage4_split as s4

DEFAULT_CSV = HERE.parent / "guangzhou_all_atom" / "data" / "raw" / "CycPeptMPDB_Peptide_All.csv"
GZ_DATA = HERE.parent / "guangzhou_all_atom" / "data"


def _deps():
    d = {"python": platform.python_version()}
    try:
        import rdkit
        d["rdkit"] = rdkit.__version__
    except Exception as e:
        d["rdkit"] = f"MISSING ({e})"
    try:
        from rdkit.Chem.MolStandardize import rdMolStandardize  # noqa
        d["rdkit_MolStandardize"] = True
    except Exception:
        d["rdkit_MolStandardize"] = False
    try:
        from rdkit import Chem
        d["rdkit_MolFromHELM"] = hasattr(Chem, "MolFromHELM")
    except Exception:
        d["rdkit_MolFromHELM"] = False
    return d


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", type=Path, default=HERE / "cyclic_corpus_v1")
    ap.add_argument("--csv", type=Path, default=DEFAULT_CSV, help="local CycPeptMPDB CSV")
    ap.add_argument("--staging", type=Path, default=None,
                    help="dir with extracted S3 datasets (cremp/, pepbdb/, bindingdb_peptide/)")
    ap.add_argument("--limit", type=int, default=None, help="cap CycPeptMPDB rows (quick smoke)")
    ap.add_argument("--no-tautomer", action="store_true",
                    help="skip tautomer canonicalization in stage2 (faster; slightly weaker dedup)")
    ap.add_argument("--dedup-key", choices=["inchikey", "std_smiles"], default="inchikey")
    ap.add_argument("--test-frac", type=float, default=0.10)
    ap.add_argument("--val-frac", type=float, default=0.10)
    ap.add_argument("--gate-n", type=int, default=200, help="HELM round-trip gate sample size")
    args = ap.parse_args(argv)

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    t0 = datetime.now(timezone.utc)
    manifest = {"built_at_utc": t0.isoformat(), "deps": _deps(), "args": {
        "csv": str(args.csv), "staging": str(args.staging) if args.staging else None,
        "limit": args.limit, "dedup_key": args.dedup_key,
        "test_frac": args.test_frac, "val_frac": args.val_frac}}

    # ---- load ----
    print("== load sources ==", file=sys.stderr)
    records = sources.load_all(args.csv, args.staging, GZ_DATA, limit=args.limit)
    manifest["stage0_load"] = {"total_loaded": len(records),
                               "by_source": _count_by(records, "source")}
    if not records:
        print("no records loaded — is the CycPeptMPDB CSV present?", file=sys.stderr)
        return 2

    # ---- FIX #1: HELM canonicalization + gate ----
    print("== stage1: HELM canonicalization (fix #1) ==", file=sys.stderr)
    manifest["stage1_helm"] = s1.run(records)
    manifest["stage1_helm"]["roundtrip_gate"] = s1.roundtrip_gate(records, n=args.gate_n)

    # ---- FIX #2: standardization + priority-merge dedup ----
    print("== stage2: SMILES standardization + priority-merge dedup (fix #2) ==", file=sys.stderr)
    records, s2stats = s2.run(records, do_tautomer=not args.no_tautomer, dedup_key=args.dedup_key)
    manifest["stage2_standardize_dedup"] = s2stats

    # ---- FIX #3: provenance validation + tally ----
    print("== stage3: conformer provenance (fix #3) ==", file=sys.stderr)
    manifest["stage3_provenance"] = s3.run(records)

    # ---- FIX #4: cyclic-aware split + FREEZE eval + leakage report ----
    print("== stage4: cyclic-aware split + freeze eval + leakage report (fix #4) ==", file=sys.stderr)
    split_report = s4.run(records, test_frac=args.test_frac, val_frac=args.val_frac)
    manifest["stage4_split"] = split_report

    # ---- write outputs ----
    schema.dump_jsonl(records, out / "records.jsonl")
    eval_frozen = [r for r in records if r.get("eval_frozen")]
    premium = [r for r in records if r.get("premium_eval")]
    train = [r for r in records if r.get("split") == "train"]
    schema.dump_jsonl(eval_frozen, out / "eval_frozen.jsonl")
    schema.dump_jsonl(premium, out / "premium_eval.jsonl")
    schema.dump_jsonl(train, out / "train.jsonl")

    leakage_report = {
        "stage1_helm_gate": manifest["stage1_helm"]["roundtrip_gate"],
        "stage2_dedup": s2stats,
        "stage3_provenance": manifest["stage3_provenance"],
        "stage4_split_and_leakage": split_report,
        "final_counts": {
            "unique_records": len(records),
            "train": len(train),
            "eval_frozen": len(eval_frozen),
            "premium_eval": len(premium),
        },
    }
    with open(out / "leakage_report.json", "w") as f:
        json.dump(leakage_report, f, indent=2)

    manifest["outputs"] = {
        "records.jsonl": len(records),
        "eval_frozen.jsonl": len(eval_frozen),
        "premium_eval.jsonl": len(premium),
        "train.jsonl": len(train),
    }
    manifest["elapsed_sec"] = round((datetime.now(timezone.utc) - t0).total_seconds(), 1)
    with open(out / "manifest.json", "w") as f:
        json.dump(manifest, f, indent=2)

    # ---- console summary ----
    print("\n== cyclic_corpus_v1 BUILD SUMMARY ==")
    print(json.dumps({
        "loaded": manifest["stage0_load"],
        "helm_gate": manifest["stage1_helm"]["roundtrip_gate"].get("pass_rate"),
        "unique_after_dedup": s2stats["unique_after_dedup"],
        "duplicates_removed": s2stats["duplicates_removed"],
        "by_provenance": manifest["stage3_provenance"]["by_provenance"],
        "split_counts": split_report.get("split_counts"),
        "leakage_median_tanimoto": split_report.get("leakage_gate", {}).get("median"),
        "leakage_PASS": split_report.get("leakage_gate", {}).get("PASS"),
        "outputs_dir": str(out),
    }, indent=2))
    return 0


def _count_by(records, key):
    c = {}
    for r in records:
        c[r.get(key)] = c.get(r.get(key), 0) + 1
    return c


if __name__ == "__main__":
    raise SystemExit(main())
