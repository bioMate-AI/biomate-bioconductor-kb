#!/usr/bin/env python3
"""m2_eval.py — leakage-honest M2 stage-2b acceptance eval for the cyclic-mid-trained LATENT-DIFFUSION
generator, on the FROZEN per-molecule CREMP hold-out. UNCONDITIONAL (no receptor): reports the subset of the
7-metric panel that is meaningful WITHOUT a target, and loudly marks the rest N/A (needs 2c bound complexes).

============================================================================================================
WHICH PANEL METRICS ARE VALID FOR UNCONDITIONAL 2b vs. NEED A TARGET (2c)?  (traced against cal_metrics.py)
============================================================================================================
cal_metrics.py computes DockQ / RMSD(CA)-vs-reference / Slide AAR by reading a REFERENCE complex PDB with a
receptor chain + ligand chain and comparing the generated pose to it. For UNCONDITIONAL 2b there is NO
receptor and NO target pose, so:

  VALID for 2b (computed here, no target needed):
    * Validity — generated peptides decode to real residues with sane backbone geometry (fraction non-degenerate)
    * Ring-closure — head-to-tail macrolactam intact (M0/M1's ring_closed(); the M2 latent-quality signal)
    * Sequence / Struct / Codesign Diversity — across N unconditional samples (evaluation.diversity, verbatim)
    * Consistency — seq-cluster vs struct-cluster agreement across samples (evaluation.diversity, verbatim)
    * Latent-decode consistency — the diffusion samples land in a region the FROZEN v1 AE decodes to valid
      geometry (the real 2b question: does the warm-started denoiser generate the v1 latent well?)
    * (reference-anchored, honest) Sampled-vs-CREMP nearest-neighbour Cα RMSD — how close a sampled ring is
      to the nearest held-out CREMP conformer of the SAME length. NOT a binding metric; a distribution-match
      sanity signal. Reported as context, never as evidence of binding.

  N/A for 2b — REQUIRES A TARGET (deferred to 2c, needs D2 bound complexes):
    * DockQ, DockQ>=0.23/0.49/0.80 — interface quality vs a receptor. No receptor in 2b.
    * RMSD(CA) / RMSD(full-atom) vs a reference BOUND pose — no reference pose without a target.
    * Slide AAR — sequence recovery vs a KNOWN target-binder sequence. Unconditional has no reference binder.
    * dG (evaluation/dG) — binding free energy vs a receptor. No receptor.
  These are explicitly listed as N/A in the report so the panel is never silently DockQ-only (work-plan rule).

REUSE (do NOT reinvent — CLAUDE.md): m0_frozen_probe for the frozen hold-out loader + ring_closed + block
tensorization; evaluation.diversity for the diversity/consistency panel (the same code cal_metrics.py calls).

USAGE
  python3 m2_eval.py \
      --m2-ckpt   ./ckpts/m2_ldm_midtrain/version_0/checkpoint/epochXX_stepYY.ckpt \
      --cremp-dir ./data/cremp \
      --n-test-mols 100 --n-samples 8 --gpu 0 --out ./m2_eval_result.json
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

import m0_frozen_probe as m0     # frozen hold-out loader + ring_closed + block->batch tensorization
import m1_closure_ae             # noqa: F401  registers ClosureAwareAutoEncoder (the v1 AE class, for unpickle)
import m2_peptide_ldm            # noqa: F401  registers PeptideOnlyLDMPepDesign (for unpickle)


def _load_ldm(ckpt_path: str, device):
    import torch
    import models  # noqa: F401  registers AutoEncoder / LDMPepDesign

    obj = torch.load(ckpt_path, map_location="cpu", weights_only=False)
    if not hasattr(obj, "sample") or not hasattr(obj, "autoencoder"):
        raise TypeError(f"--m2-ckpt is a {type(obj).__name__}; expected an (Peptide)LDMPepDesign.")
    obj.to(device)
    obj.eval()
    return obj


def _sample_unconditional(ldm, n_res: int, ref_blocks, device):
    """Sample ONE peptide of length n_res unconditionally, then decode via the frozen v1 AE. We build a
    peptide-only batch of the right size (LDMPepDesign.sample zeroes the masked latent, so the reference
    sequence/coords only fix the SHAPE — n_res, position_ids — not the content). Returns (rec_X[N,14,3],
    rec_S[str], atom_mask[N,14])."""
    import numpy as np
    import torch

    # reuse M0's exact peptide-only tensorization (MAX_N_ATOM=14 padding, mask=all-generate, pos=1..n)
    batch, _true_X, true_atom_mask = m0._blocks_to_batch(ref_blocks, device)
    with torch.no_grad():
        rec_X, rec_S, _ppls = ldm.sample(
            batch["X"], batch["S"], batch["mask"], batch["position_ids"],
            batch["lengths"], batch["atom_mask"], L=None,
            sample_opt={"pbar": False, "energy_func": None, "energy_lambda": 0.0, "autoencoder_n_iter": 1},
            return_tensor=True, optimize_sidechain=False,
        )
    if rec_X is None:
        return None
    rec = rec_X.detach().cpu().numpy() if hasattr(rec_X, "detach") else np.array(rec_X)
    if rec.shape[0] != n_res:
        return None
    seq = rec_S if isinstance(rec_S, str) else None
    if seq is None and rec_S is not None:
        from data.format import VOCAB
        seq = "".join(VOCAB.idx_to_symbol(int(s)) for s in rec_S.detach().cpu().numpy())
    return rec, seq, true_atom_mask.numpy().astype(bool)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--m2-ckpt", type=Path, default=os.environ.get("M2_CKPT"), required=False)
    ap.add_argument("--cremp-dir", type=Path, default=os.environ.get("CREMP_DIR"), required=False)
    ap.add_argument("--n-test-mols", type=int, default=int(os.environ.get("N_TEST_MOLS", "100")))
    ap.add_argument("--n-samples", type=int, default=int(os.environ.get("N_SAMPLES", "8")),
                    help="unconditional samples per length-slot (>=2 required for diversity/consistency)")
    ap.add_argument("--gpu", type=int, default=int(os.environ.get("GPU", "0")))
    ap.add_argument("--out", type=Path, default=os.environ.get("OUT", "m2_eval_result.json"))
    args = ap.parse_args(argv)

    if not args.m2_ckpt or not Path(args.m2_ckpt).is_file():
        print(f"FATAL: --m2-ckpt not found: {args.m2_ckpt}", file=sys.stderr)
        return 2
    if not args.cremp_dir or not Path(args.cremp_dir).exists():
        print(f"FATAL: --cremp-dir not found: {args.cremp_dir}", file=sys.stderr)
        return 2

    import numpy as np
    import torch
    from evaluation import diversity

    device = torch.device("cpu" if args.gpu == -1 else f"cuda:{args.gpu}")
    t0 = time.time()
    report = {
        "experiment": "M2 stage-2b unconditional cyclic-mid-train eval (frozen per-molecule CREMP hold-out)",
        "utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "m2_ckpt": str(args.m2_ckpt),
        "n_samples_per_slot": args.n_samples,
        "panel_NA_needs_target_2c": [
            "DockQ", "DockQ>=0.23", "DockQ>=0.49", "DockQ>=0.80",
            "RMSD(CA)_vs_bound_ref", "RMSD(full-atom)_vs_bound_ref", "Slide AAR", "dG",
        ],
        "panel_valid_2b": [
            "validity", "ring_closure", "Sequence Diversity", "Struct Diversity",
            "Codesign Diversity", "Consistency", "latent_decode_consistency",
            "sampled_vs_cremp_nn_ca_rmsd(context_only)",
        ],
    }
    try:
        print("[1/3] loading held-out CREMP molecules (SAME split as M0/M1) ...", flush=True)
        cremp_mols = m0.load_cremp_test_molecules(args.cremp_dir, args.n_test_mols)
        report["cremp_test_mols_loaded"] = len(cremp_mols)

        print("[2/3] loading M2 LDM + unconditional sampling ...", flush=True)
        ldm = _load_ldm(str(args.m2_ckpt), device)

        n_valid = 0
        n_ring_closed = 0
        n_total = 0
        per_slot_seqs, per_slot_cas = [], []       # for diversity: list per molecule-slot
        nn_rmsds = []                               # sampled-vs-nearest-CREMP context signal
        for mol in cremp_mols:
            # load_cremp_test_molecules returns {"id","seq","blocks","provenance"} where each block is
            # {"abrv","symbol","atoms":[{"name","element","coord"}]} — the exact shape _blocks_to_batch wants.
            blocks = mol.get("blocks")
            if not blocks:
                continue
            n_res = len(blocks)

            def _ca_of(blk):
                for a in blk["atoms"]:
                    if a["name"] == "CA":
                        return a["coord"]
                return blk["atoms"][min(1, len(blk["atoms"]) - 1)]["coord"]
            ref_ca = np.array([_ca_of(b_) for b_ in blocks])
            slot_seqs, slot_cas = [], []
            for _ in range(args.n_samples):
                out = _sample_unconditional(ldm, n_res, blocks, device)
                n_total += 1
                if out is None:
                    continue
                rec, seq, am = out
                # validity: reconstructed CA coords finite + not collapsed to a point
                ca = rec[:, 1]
                finite = np.isfinite(ca).all()
                spread = float(np.linalg.norm(ca - ca.mean(0), axis=-1).mean()) if finite else 0.0
                valid = bool(finite and spread > 0.5)  # >0.5A mean radius => not a collapsed blob
                if valid:
                    n_valid += 1
                if m0.ring_closed(rec, am):
                    n_ring_closed += 1
                if seq is not None:
                    slot_seqs.append(seq)
                slot_cas.append(ca)
                if ref_ca is not None and ca.shape == ref_ca.shape:
                    # aligned-free NN Cα RMSD to this slot's reference conformer (context only)
                    nn_rmsds.append(float(np.sqrt(((ca - ref_ca) ** 2).sum(-1).mean())))
            if len(slot_cas) >= 2:
                per_slot_seqs.append(slot_seqs if len(slot_seqs) == len(slot_cas) else None)
                per_slot_cas.append(np.array(slot_cas))

        # aggregate validity + ring-closure
        report["validity_rate"] = (n_valid / n_total) if n_total else float("nan")
        report["ring_closure_rate"] = (n_ring_closed / n_total) if n_total else float("nan")
        report["n_samples_total"] = n_total

        # diversity + consistency across samples, per slot, then averaged (same code cal_metrics.py calls)
        seq_divs, struct_divs, co_divs, consistencies = [], [], [], []
        for seqs, cas in zip(per_slot_seqs, per_slot_cas):
            if not seqs:
                # no sequences recovered for this slot -> structure diversity only (codesign needs both)
                struct_divs.append(diversity.struct_diversity(cas)[0])
                continue
            sd, std, cod, cons = diversity.diversity(seqs, cas)
            seq_divs.append(sd); struct_divs.append(std); co_divs.append(cod)
            if cons is not None:
                consistencies.append(float(cons))
        _mean = lambda xs: (sum(xs) / len(xs)) if xs else float("nan")
        report["Sequence Diversity"] = _mean(seq_divs)
        report["Struct Diversity"] = _mean(struct_divs)
        report["Codesign Diversity"] = _mean(co_divs)
        report["Consistency"] = _mean(consistencies)
        report["latent_decode_consistency"] = report["validity_rate"]  # frozen-AE-decodes-to-valid rate
        report["sampled_vs_cremp_nn_ca_rmsd_median"] = (
            float(np.median(nn_rmsds)) if nn_rmsds else float("nan"))

        print("[3/3] summarising ...", flush=True)
        report["summary"] = {
            "validity_rate": report["validity_rate"],
            "ring_closure_rate": report["ring_closure_rate"],
            "m1_v1_ae_recon_ring_closure": 0.33,   # the frozen AE's OWN ring-closure ceiling (M1 v1)
            "note": ("2b is unconditional: DockQ/Slide-AAR/dG are N/A (need a target -> 2c). The 2b signal "
                     "is whether the warm-started denoiser generates the v1 latent such that the FROZEN v1 AE "
                     "decodes VALID, RING-CLOSED, DIVERSE macrocycles. Ring-closure is bounded above by the "
                     "AE's own 0.33 reconstruction ceiling (M1 v1)."),
        }
        report["elapsed_sec"] = round(time.time() - t0, 1)
        report["status"] = "ok"
    except Exception as e:
        report["status"] = "error"
        report["error"] = f"{type(e).__name__}: {e}"
        report["traceback"] = traceback.format_exc()
        print(report["traceback"], file=sys.stderr)

    Path(args.out).write_text(json.dumps(report, indent=2, default=float))
    print(json.dumps(report.get("summary", {"status": report["status"]}), indent=2, default=float))
    return 0 if report.get("status") == "ok" else 1


if __name__ == "__main__":
    raise SystemExit(main())
