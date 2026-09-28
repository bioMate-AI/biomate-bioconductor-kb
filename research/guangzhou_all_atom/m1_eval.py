#!/usr/bin/env python3
"""m1_eval.py — leakage-honest M1 acceptance eval on the FROZEN per-molecule CREMP hold-out.

Reports the SAME metrics as m0_frozen_probe.py (reconstruction RMSD-Cα + ring-closure validity), on the
IDENTICAL held-out test molecules (same sequence-hash split, same 300 lowest-energy conformers), so M1
is directly comparable to the M0 baseline (ring-closure 0.32, RMSD-Cα 1.05 A). This is the M1 STRENGTH
GATE input: does mid-training on CREMP + the M4 closure term recover ring closure without wrecking the
backbone?

REUSE (do NOT reinvent — everything comes from m0_frozen_probe):
  * load_cremp_test_molecules  — the frozen per-molecule hold-out loader (per-molecule split, 1
    lowest-energy conformer each). Guarantees the SAME hold-out M0 used.
  * reconstruct / ring_closed / stereo_preserved / evaluate_init — the deterministic encode->decode
    probe + the exact validity metrics. We call evaluate_init on the M1-trained AE.
  * latent_ring_break_test (inside evaluate_init) — the Gemini interpolation ring-break signal.

WHAT'S NEW HERE: just loading the M1-trained checkpoint (a bare ClosureAwareAutoEncoder saved by the
ClosureAETrainer via torch.save(model)) and, optionally, re-running the M0 linear-init arm side-by-side
for an apples-to-apples before/after table.

USAGE
  python3 m1_eval.py \
      --m1-ckpt   ./ckpts/m1_ae_midtrain/version_0/checkpoint/epochXX_stepYY.ckpt \
      --cremp-dir ./data/cremp \
      --baseline-ckpt ./data/epoch221.ckpt \
      --n-test-mols 300 --gpu 0 --out ./m1_eval_result.json
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
import traceback
from pathlib import Path

ROOT = Path(__file__).resolve().parent
RUNTIME = ROOT / "runtime" / "PepGLAD"
for p in (str(RUNTIME), str(ROOT)):
    if p not in sys.path:
        sys.path.insert(0, p)

# Reuse the M0 machinery wholesale.
import m0_frozen_probe as m0
import m1_closure_ae  # noqa: F401  registers ClosureAwareAutoEncoder so torch.load can unpickle it


def _load_ae(ckpt_path: str, device):
    import torch
    import models  # noqa: F401  registers AutoEncoder / LDMPepDesign

    obj = torch.load(ckpt_path, map_location="cpu", weights_only=False)
    # M1 checkpoints are bare (Closure)AutoEncoder; epoch-221 baseline is an LDMPepDesign.
    if hasattr(obj, "autoencoder"):
        ae = obj.autoencoder
    else:
        ae = obj
    ae.to(device)
    ae.eval()
    for p in ae.parameters():
        p.requires_grad = False
    return ae


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--m1-ckpt", type=Path, default=os.environ.get("M1_CKPT"), required=False,
                    help="trained M1 AE checkpoint (bare ClosureAwareAutoEncoder)")
    ap.add_argument("--baseline-ckpt", type=Path, default=os.environ.get("LDM_CKPT"),
                    help="OPTIONAL epoch-221 baseline (re-run the M0 linear arm for a before/after table)")
    ap.add_argument("--cremp-dir", type=Path, default=os.environ.get("CREMP_DIR"), required=False)
    ap.add_argument("--n-test-mols", type=int, default=int(os.environ.get("N_TEST_MOLS", "300")))
    ap.add_argument("--gpu", type=int, default=int(os.environ.get("GPU", "0")))
    ap.add_argument("--out", type=Path, default=os.environ.get("OUT", "m1_eval_result.json"))
    args = ap.parse_args(argv)

    if not args.m1_ckpt or not Path(args.m1_ckpt).is_file():
        print(f"FATAL: --m1-ckpt not found: {args.m1_ckpt}", file=sys.stderr)
        return 2
    if not args.cremp_dir or not Path(args.cremp_dir).exists():
        print(f"FATAL: --cremp-dir not found: {args.cremp_dir}", file=sys.stderr)
        return 2

    import torch

    device = torch.device("cpu" if args.gpu == -1 else f"cuda:{args.gpu}")
    t0 = time.time()
    report = {
        "experiment": "M1 AE mid-train eval (frozen per-molecule CREMP hold-out)",
        "utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "m1_ckpt": str(args.m1_ckpt),
        "m0_baseline": {"ring_closure_valid_rate": 0.32, "rmsd_ca_mean": 1.05,
                        "note": "reported M0 verdict on 300 held-out CREMP mols"},
    }
    try:
        print("[1/3] loading held-out CREMP molecules (SAME split as M0) ...", flush=True)
        cremp_mols = m0.load_cremp_test_molecules(args.cremp_dir, args.n_test_mols)
        report["cremp_test_mols_loaded"] = len(cremp_mols)
        print(f"  loaded {len(cremp_mols)} test molecules", flush=True)

        print("[2/3] evaluating M1-trained AE ...", flush=True)
        m1_ae = _load_ae(str(args.m1_ckpt), device)
        report["m1"] = m0.evaluate_init("m1_midtrain", m1_ae, cremp_mols, [], device)

        if args.baseline_ckpt and Path(args.baseline_ckpt).is_file():
            print("[2b/3] re-running epoch-221 baseline arm (before/after) ...", flush=True)
            base_ae = _load_ae(str(args.baseline_ckpt), device)
            report["baseline_rerun"] = m0.evaluate_init("linear_epoch221", base_ae, cremp_mols, [], device)

        print("[3/3] summarising ...", flush=True)
        m1c = report["m1"]["cremp"]
        summary = {
            "m1_ring_closure_valid_rate": m1c["ring_closure_valid_rate"],
            "m1_rmsd_ca_mean": m1c["rmsd_ca_mean"],
            "m0_ring_closure_valid_rate": 0.32,
            "m0_rmsd_ca_mean": 1.05,
            "closure_delta_vs_m0": (m1c["ring_closure_valid_rate"] - 0.32
                                    if m1c["ring_closure_valid_rate"] == m1c["ring_closure_valid_rate"] else None),
        }
        # Strength gate context (RINGER coverage-recall 79.7% is the M1 bar per the work plan).
        summary["ringer_bar_ring_closure"] = 0.797
        summary["meets_ringer_bar"] = (
            m1c["ring_closure_valid_rate"] >= 0.797
            if m1c["ring_closure_valid_rate"] == m1c["ring_closure_valid_rate"] else False
        )
        report["summary"] = summary
        report["elapsed_sec"] = round(time.time() - t0, 1)
        report["status"] = "ok"
    except Exception as e:
        report["status"] = "error"
        report["error"] = f"{type(e).__name__}: {e}"
        report["traceback"] = traceback.format_exc()
        print(report["traceback"], file=sys.stderr)

    Path(args.out).write_text(json.dumps(report, indent=2))
    print(json.dumps(report.get("summary", {"status": report["status"]}), indent=2))
    return 0 if report.get("status") == "ok" else 1


if __name__ == "__main__":
    raise SystemExit(main())
