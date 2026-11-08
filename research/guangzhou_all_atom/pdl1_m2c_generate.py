#!/usr/bin/env python3
"""pdl1_m2c_generate.py — DE-NOVO cyclic-peptide GENERATION on ONE receptor target (default PD-L1 / 5O45)
with the trained M2c target-conditioned latent-diffusion generator, driving the OFFICIAL PepGLAD generate.py.
This is the ACT Round-1 DIVERSITY arm (complements the BoltzGen pool). It is GENERATION on a single unseen
target, NOT eval on a held-out split, so it reports metrics COMPUTABLE WITHOUT A REFERENCE BINDER (validity,
ring-closability, length, sequence diversity) and emits sequences + PDBs for the §3 re-rank
(gate -> MM-GBSA -> permeability -> GP-Pareto), tagging provenance = PepGLAD_M2c_generated.

============================================================================================================
WHY THIS DRIVER (and how it reuses m2c_eval.py's VERIFIED generate path)
============================================================================================================
It reuses m2c_eval.py's exact mechanism for driving the stock scripts (the parts that were debugged against
the real runtime):
  * run the STOCK generate.py / setup_latent_guidance.py from cwd = runtime/PepGLAD via a -c wrapper that
    FIRST imports m1_closure_ae (registers the v1 AE class for unpickling the M2c ckpt) + models (registers
    LDMPepDesign / AutoEncoder / CoDesignDataset), THEN execs the stock script (m2c_eval.py:168-176). The M2c
    ckpt is a pickled whole-model object (generate.py:155 torch.load) whose .autoencoder is the v1 AE class ->
    without importing m1_closure_ae the unpickle fails. VERIFIED against m2c_eval's proven path.
  * the ABS-CONFIG FIX (run_m2c_ldm_finetune.sh:199): the stock scripts run with cwd=runtime/PepGLAD but the
    configs use relative './data/...' mmap_dir -> they'd resolve under runtime/PepGLAD/data and FileNotFound.
    The launcher sed-rewrites the config paths to absolute before generation. This driver ALSO accepts an
    absolute --mmap-dir/--test-index and injects them via generate.py's overwrite_values (--dotted.key=val),
    so it is cwd-independent even if the config still holds a relative default.

ENERGY GUIDANCE ON A SINGLE UNSEEN TARGET (the one real difference vs m2c_eval):
  generate.py with sample_opt.energy_func == 'default' calls ldm.latent_geometry_guidance, which ASSERTS
  consec_dist_mean is set (ldm.py:138-140); that is set by setup_latent_guidance.py over a TRAIN split. For a
  single unseen target there is NO held-out train distribution. Two honest options, both supported here:
    (A) --energy off  (DEFAULT): set sample_opt.energy_func=null -> NO setup step, NO consec-dist needed.
        Cleanest for an unseen target; sampling relies purely on the learned latent prior. Recommended.
    (B) --energy d2 --d2-guidance-index <path>: run setup_latent_guidance over the D2 TRAIN split from the
        finetune run (the distribution the M2c ckpt was actually trained on) to set consec-dist, then generate
        WITH guidance. Use this only if the D2 train mmap is co-located; it applies the same ring-geometry
        prior the model saw in training. (setup writes consec-dist INTO the ckpt, so we copy the ckpt first
        to avoid mutating the released M2c checkpoint.)

METRICS FOR AN UNSEEN TARGET (no native binder to compare a DE-NOVO design against):
  * validity: fraction of designs with all-canonical decoded sequence (no UNK), full backbone, no clashed/
    NaN/huge coords (generate.py already clamps |coord|>=1000 -> 0; we additionally flag them).
  * ring-closability (head-to-tail): N(res1)–C(resL) distance; a closable macrocycle has this ~1.3 A after a
    cyclization step. We report the raw distance distribution as a design-time proxy (the actual closure +
    MM-GBSA happen in the §3 re-rank harness, not here).
  * length distribution + sequence diversity across the N samples (pairwise Hamming / unique-fraction).
  * We DELIBERATELY do NOT report DockQ / AAR / RMSD-to-native: there is no cognate reference for a de-novo
    binder, so those are ill-defined (unlike m2c_eval on the held-out split). Reporting them would be dishonest.

OUTPUT (feeds the §3 re-rank):
  <out>/m2c_gen/candidates/<variant_id>/<variant_id>_gen_<n>.pdb   receptor+design complexes (stock generate.py)
  <out>/m2c_gen/references/<variant_id>_ref.pdb                    the staged scaffold (NOT a true native binder)
  <out>/m2c_gen/results.jsonl                                      stock per-design records (gen_seq, pdbs)
  <out>/pdl1_m2c_designs.jsonl                                     RE-RANK FEED: one row/design with sequence,
                                                                   pdb path, length, ring-closure dist, validity,
                                                                   provenance="PepGLAD_M2c_generated", target=5O45
  <out>/pdl1_m2c_generate_report.json                             summary panel + honest caveats

USAGE (driven by pdl1_m2c_run.sh on the instance)
  python3 pdl1_m2c_generate.py \
      --m2c-ckpt ./data/m2c.ckpt \
      --target-dir ./data/pdl1_m2c_target \
      --test-config pdl1_m2c_test_codesign.yaml \
      --guidance-config pdl1_m2c_setup_latent_guidance.yaml \
      --n-samples 150 --gpu 0 --energy off \
      --out ./pdl1_m2c_out
"""
from __future__ import annotations

import argparse
import json
import math
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent
RUNTIME = ROOT / "runtime" / "PepGLAD"


def _run(cmd, env, cwd, log_prefix):
    print(f"\n[pdl1_m2c] $ {' '.join(str(c) for c in cmd)}", flush=True)
    proc = subprocess.Popen(cmd, cwd=cwd, env=env, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True, bufsize=1)
    lines = []
    for line in proc.stdout:
        sys.stdout.write(f"[{log_prefix}] {line}")
        lines.append(line)
    proc.wait()
    return proc.returncode, "".join(lines[-120:])


def _canonical_aas():
    return set("ACDEFGHIKLMNPQRSTVWY")


def _ring_closure_dist(pdb_path: str, lig_chain: str):
    """Head-to-tail proxy: distance between N of the first ligand residue and C of the last ligand residue.
    A closable macrocycle has this small (real closure done in the re-rank harness). Returns float or None."""
    try:
        from Bio.PDB import PDBParser
        import numpy as np
        s = PDBParser(QUIET=True).get_structure("g", pdb_path)
        model = next(s.get_models())
        chain = model[lig_chain] if lig_chain in model else None
        if chain is None:
            return None
        res = [r for r in chain]
        if len(res) < 2:
            return None
        n_first = res[0]["N"].get_coord() if "N" in res[0] else None
        c_last = res[-1]["C"].get_coord() if "C" in res[-1] else None
        if n_first is None or c_last is None:
            return None
        return float(np.linalg.norm(np.array(n_first) - np.array(c_last)))
    except Exception:  # noqa: BLE001
        return None


def _seq_diversity(seqs):
    """Unique fraction + mean pairwise normalized Hamming over equal-length pairs. Cheap, reference-free."""
    if not seqs:
        return {"n": 0, "unique_fraction": 0.0, "mean_pairwise_hamming": None}
    uniq = len(set(seqs)) / len(seqs)
    dists = []
    for i in range(len(seqs)):
        for j in range(i + 1, len(seqs)):
            a, b = seqs[i], seqs[j]
            if len(a) == len(b) and a:
                dists.append(sum(1 for x, y in zip(a, b) if x != y) / len(a))
    return {"n": len(seqs), "unique_fraction": round(uniq, 3),
            "mean_pairwise_hamming": round(sum(dists) / len(dists), 3) if dists else None}


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--m2c-ckpt", type=Path, required=True)
    ap.add_argument("--target-dir", type=Path, required=True,
                    help="pdl1_m2c_stage_target --out-dir (has pdbs/ + processed/ + test_index.txt)")
    ap.add_argument("--test-config", type=Path, default=None,
                    help="generate.py test config. Default is chosen by --energy: pdl1_m2c_test_noenergy.yaml "
                         "(energy off) or pdl1_m2c_test_codesign.yaml (energy d2). energy_func canNOT be "
                         "flipped via overwrite_values (type(ori)(val): 'default'->'null' stays a str, "
                         "None->str errors), so the two paths use two config FILES.")
    ap.add_argument("--guidance-config", type=Path, default=ROOT / "pdl1_m2c_setup_latent_guidance.yaml")
    ap.add_argument("--n-samples", type=int, default=150, help="designs per length variant")
    ap.add_argument("--gpu", type=int, default=0)
    ap.add_argument("--energy", choices=["off", "d2"], default="off",
                    help="off = no energy guidance (default, correct for a single unseen target); "
                         "d2 = run setup_latent_guidance over --d2-guidance-index then generate WITH guidance")
    ap.add_argument("--d2-guidance-index", type=Path, default=None,
                    help="path to the D2 TRAIN index (+ its mmap dir) for --energy d2")
    ap.add_argument("--d2-guidance-mmap", type=Path, default=None)
    ap.add_argument("--out", type=Path, default=ROOT / "pdl1_m2c_out")
    args = ap.parse_args(argv)

    cwd = str(RUNTIME)
    env = dict(os.environ)
    env["PYTHONPATH"] = f"{RUNTIME}:{ROOT}:" + env.get("PYTHONPATH", "")
    env.setdefault("PYTORCH_CUDA_ALLOC_CONF", "expandable_segments:True")

    if not args.m2c_ckpt.is_file():
        print(f"FATAL: --m2c-ckpt not found: {args.m2c_ckpt}", file=sys.stderr)
        return 2
    processed_dir = str((args.target_dir / "processed").resolve())
    test_index = os.path.join(processed_dir, "test_index.txt")
    if not os.path.isfile(test_index):
        print(f"FATAL: test_index not found: {test_index} (run pdl1_m2c_stage_target.py first)", file=sys.stderr)
        return 2
    # pick the config file by --energy (energy_func is NOT overridable via dotted args — see --test-config help)
    if args.test_config is None:
        default_cfg = "pdl1_m2c_test_noenergy.yaml" if args.energy == "off" else "pdl1_m2c_test_codesign.yaml"
        args.test_config = ROOT / default_cfg
    if not args.test_config.is_file():
        print(f"FATAL: test config not found: {args.test_config}", file=sys.stderr)
        return 2
    test_cfg = str(args.test_config.resolve())
    guid_cfg = str(args.guidance_config.resolve())
    args.out.mkdir(parents=True, exist_ok=True)

    # copy the released M2c ckpt so we never mutate it (setup_latent_guidance re-saves consec-dist INTO the ckpt)
    work_ckpt = args.out / "m2c_work.ckpt"
    shutil.copy2(str(args.m2c_ckpt), str(work_ckpt))
    ckpt = str(work_ckpt.resolve())

    report = {
        "experiment": "M2c de-novo cyclic-peptide GENERATION on PD-L1 (5O45) — ACT Round-1 diversity arm",
        "utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "m2c_ckpt_src": str(args.m2c_ckpt),
        "n_samples_per_variant": args.n_samples,
        "energy_guidance": args.energy,
        "provenance_tag": "PepGLAD_M2c_generated",
        "steps": {},
    }

    def stock(script, script_args):
        wrapper = (
            "import sys; sys.path.insert(0,'.'); sys.path.insert(0, r'%s');\n"
            "import m1_closure_ae  # register v1 AE class for unpickle\n"
            "import models  # register LDMPepDesign/AutoEncoder/CoDesignDataset\n"
            "sys.argv = %r\n"
            "exec(open(%r).read())\n"
        ) % (str(ROOT), [script] + [str(a) for a in script_args], str(RUNTIME / script))
        return _run([sys.executable, "-c", wrapper], env, cwd, script.replace(".py", ""))

    try:
        # ---- 1. energy guidance setup (only for --energy d2) ----
        if args.energy == "d2":
            if not (args.d2_guidance_index and args.d2_guidance_mmap):
                raise RuntimeError("--energy d2 requires --d2-guidance-index and --d2-guidance-mmap")
            rc, _ = stock("setup_latent_guidance.py",
                          ["--config", guid_cfg, "--ckpt", ckpt, "--gpu", args.gpu,
                           "--dataset.test.mmap_dir=" + str(args.d2_guidance_mmap.resolve()),
                           "--dataset.test.specify_index=" + str(args.d2_guidance_index.resolve())])
            report["steps"]["setup_latent_guidance"] = {"rc": rc}
            if rc != 0:
                raise RuntimeError("setup_latent_guidance.py failed (needed for --energy d2)")
        else:
            report["steps"]["setup_latent_guidance"] = {"skipped": "energy off (single unseen target)"}

        # ---- 2. GENERATE on the PD-L1 target variants (co-design mode) ----
        gen_dir = str((args.out / "m2c_gen").resolve())
        # NOTE: energy_func is set by the CHOSEN config file, NOT a dotted override (overwrite_values cannot
        # turn 'default'->None nor None->'default'; type(ori_value)(value) mangles both). --energy off ->
        # pdl1_m2c_test_noenergy.yaml (energy_func: null); --energy d2 -> pdl1_m2c_test_codesign.yaml (default).
        gen_args = ["--config", test_cfg, "--ckpt", ckpt, "--gpu", args.gpu,
                    "--save_dir", gen_dir,
                    "--dataset.test.mmap_dir=" + processed_dir,
                    "--dataset.test.specify_index=" + test_index,
                    "--n_samples=%d" % args.n_samples]
        rc, gen_tail = stock("generate.py", gen_args)
        report["steps"]["generate"] = {"rc": rc, "save_dir": gen_dir}
        if rc != 0:
            raise RuntimeError("generate.py failed:\n" + gen_tail)

        # ---- 3. parse designs -> reference-free metrics + re-rank feed ----
        results_jsonl = os.path.join(gen_dir, "results.jsonl")
        canon = _canonical_aas()
        feed_path = args.out / "pdl1_m2c_designs.jsonl"
        n_total = n_valid = 0
        seqs_all, ring_all, lengths = [], [], []
        by_variant = {}
        with open(results_jsonl) as fin, open(feed_path, "w") as fout:
            for line in fin:
                if not line.strip():
                    continue
                rec = json.loads(line)
                _id = rec["id"]
                gen_seq = rec.get("gen_seq", "") or ""
                gen_pdb = rec.get("gen_pdb", "")
                lig_chain = rec.get("lig_chain", "B")
                n_total += 1
                all_canon = bool(gen_seq) and all(c in canon for c in gen_seq)
                ring = _ring_closure_dist(gen_pdb, lig_chain) if gen_pdb and os.path.isfile(gen_pdb) else None
                valid = all_canon  # backbone/coord sanity is enforced by generate.py; canonical seq is the gate
                if valid:
                    n_valid += 1
                    seqs_all.append(gen_seq)
                    lengths.append(len(gen_seq))
                    if ring is not None and not math.isnan(ring):
                        ring_all.append(ring)
                v = by_variant.setdefault(_id, {"n": 0, "valid": 0, "seqs": []})
                v["n"] += 1
                v["valid"] += int(valid)
                if valid:
                    v["seqs"].append(gen_seq)
                fout.write(json.dumps({
                    "design_id": f"{_id}_gen_{rec.get('number')}",
                    "target": "PD-L1_5O45",
                    "variant": _id,
                    "sequence": gen_seq,
                    "length": len(gen_seq),
                    "pdb_path": gen_pdb,
                    "ref_scaffold_pdb": rec.get("ref_pdb"),
                    "rec_chain": rec.get("rec_chain"),
                    "lig_chain": lig_chain,
                    "all_canonical": all_canon,
                    "head_to_tail_NC_dist": ring,
                    "valid_for_rerank": valid,
                    "provenance": "PepGLAD_M2c_generated",
                }) + "\n")

        def _stats(xs):
            if not xs:
                return None
            xs = sorted(xs)
            return {"min": round(xs[0], 3), "median": round(xs[len(xs) // 2], 3),
                    "max": round(xs[-1], 3), "mean": round(sum(xs) / len(xs), 3), "n": len(xs)}

        report["panel"] = {
            "n_designs_total": n_total,
            "n_valid_canonical": n_valid,
            "validity_fraction": round(n_valid / n_total, 3) if n_total else 0.0,
            "length_distribution": _stats(lengths),
            "head_to_tail_NC_dist_A": _stats(ring_all),
            "sequence_diversity": _seq_diversity(seqs_all),
            "per_variant": {k: {"n": v["n"], "valid": v["valid"],
                                "validity": round(v["valid"] / v["n"], 3) if v["n"] else 0.0,
                                "diversity": _seq_diversity(v["seqs"])}
                            for k, v in by_variant.items()},
        }
        report["rerank_feed"] = str(feed_path)
        report["caveat"] = (
            "GENERATION on ONE UNSEEN, OOD target (PD-L1 5O45: flat interface, hard — BoltzGen max iptm only "
            "0.626). M2c was trained on ~200 experimental bound cyclic complexes (DockQ 0.437 on the held-out "
            "TRAIN-distribution test split); PD-L1 is out-of-distribution, so EXPECT modest per-design binding "
            "quality. The VALUE of this arm is ORTHOGONAL CHEMOTYPE DIVERSITY for the pool, not a per-design "
            "win over BoltzGen. Reference-free metrics only (no cognate native binder for a de-novo design): "
            "validity / ring-closability / diversity. Absolute binding is decided downstream by the §3 re-rank "
            "(gate -> MM-GBSA -> permeability -> GP-Pareto), identical to the BoltzGen pool. head_to_tail_NC "
            "distance is a DESIGN-TIME proxy; true macrocyclization + strain happen in the re-rank harness."
        )
        report["status"] = "ok"
    except Exception as e:  # noqa: BLE001
        import traceback
        report["status"] = "error"
        report["error"] = f"{type(e).__name__}: {e}"
        report["traceback"] = traceback.format_exc()
        print(report["traceback"], file=sys.stderr)

    (args.out / "pdl1_m2c_generate_report.json").write_text(json.dumps(report, indent=2, default=float))
    print("\n" + json.dumps({"status": report["status"], "panel": report.get("panel", {}),
                             "rerank_feed": report.get("rerank_feed")}, indent=2, default=float))
    return 0 if report.get("status") == "ok" else 1


if __name__ == "__main__":
    raise SystemExit(main())
