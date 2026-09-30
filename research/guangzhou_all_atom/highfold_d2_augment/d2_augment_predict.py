#!/usr/bin/env python3
"""
d2_augment_predict.py — D2 (2ii) PREDICTION DRIVER: for each (cyclic-peptide, receptor) job, write a Boltz YAML,
run `boltz predict`, read the confidence, CONFIDENCE-GATE, and emit a per-job record the integration step folds
into the PepGLAD format. Runs ON the spot GPU (launched by run_d2_augment_predict.sh). NO GPU launch here.

WHY Boltz (Boltz-1/2) is the predictor for the first working batch — VERIFIED, not assumed
------------------------------------------------------------------------------------------
The plan's primary pick is HighFold3/HighFold-MeD (native cyclic + N-Me/D-AA). BUT HighFold3 is an AlphaFold3
DERIVATIVE: it requires the AF3 params, which are gated behind a Google/DeepMind request-and-approval licence that
FORBIDS redistribution and is NOT auto-downloadable — so it cannot be stood up unattended on a spot instance
(blocker, flagged in the review note). Boltz, by contrast:
  * pip-installable: `pip install boltz[cuda] -U`; MIT licence (academic + commercial OK).
  * AUTO-DOWNLOADS its own open weights on first run (no gated request) — the one property a self-terminating spot
    job needs.
  * natively predicts protein-peptide COMPLEXES and supports `cyclic: true` on a chain (AF3-style cyclic offset
    encoding), plus `modifications: [{position, ccd}]` for a subset of ncAAs via CCD codes.
  * emits a confidence JSON with plddt / iptm / ptm / pair_chains_iptm -> exactly the gate the plan requires.
  * ALREADY validated installable in THIS program's spot environment (boltzgen_ourtarget.sh stands up the
    Boltz-family stack on the same AMI). So Boltz is the most RUNNABLE first batch; HighFold-MeD is the follow-up
    for the ncAA-defer list once AF3 weights are obtained (see review-note tradeoff + blocker).

Boltz YAML this driver writes (per job) — receptor chain A (linear) + cyclic peptide chain B:
    version: 1
    sequences:
      - protein: {id: A, sequence: <receptor_seq>, msa: empty}
      - protein: {id: B, sequence: <peptide_seq>, cyclic: true, msa: empty}
  (msa: empty => single-sequence mode, no MSA-server dependency on the spot box. --use_msa_server can be turned on
   with --msa-server if network to the ColabFold MSA server is allowed; single-seq is the safe default and is what
   AF3-class cyclic-peptide binder prediction typically uses for a short peptide ligand.)

CONFIDENCE GATE (plan: "keep only high-pLDDT/ipTM predictions; a wrong pocket pose is worse than no pose")
  keep IFF  iptm >= --min-iptm (default 0.6)  AND  complex_plddt >= --min-plddt (default 0.7)
  ipTM is the interface metric (does the peptide dock in a real pocket); pLDDT is per-structure confidence.
  Gated-out predictions are DROPPED (recorded with reason), not down-weighted.

OUTPUT (per kept job) -> a directory the integration step reads:
  <out-dir>/predicted/<job_id>/complex.pdb        the 2-chain predicted complex (receptor=A, peptide=B)
  <out-dir>/predicted/<job_id>/confidence.json    Boltz confidence (iptm/plddt/ptm)
  <out-dir>/predictions_manifest.jsonl            one row/job: gate result + provenance + train_only=True

TRAIN-ONLY: every kept row carries conformer_provenance="<tool>_predicted" and train_only=True. The integration
step refuses to place these in a test split; m2c_process_complexes.py's held-out test remains experimental-only.

USAGE (on the GPU box)
  python3 d2_augment_predict.py \
      --jobs ./d2_augment_jobs_v1/jobs_canonical.jsonl \
      --out-dir ./d2_augment_pred_v1 \
      --min-iptm 0.6 --min-plddt 0.7 --limit 0 [--msa-server]
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

UNIPROT_FASTA = "https://rest.uniprot.org/uniprotkb/{acc}.fasta"
AA1 = set("ACDEFGHIKLMNPQRSTVWY")


def fetch_uniprot_seq(acc: str, cache: dict, timeout: int = 30, retries: int = 3):
    acc = acc.split(",")[0].split(";")[0].strip()
    if not acc:
        return None
    if acc in cache:
        return cache[acc]
    for _ in range(retries):
        try:
            with urllib.request.urlopen(UNIPROT_FASTA.format(acc=acc), timeout=timeout) as r:
                txt = r.read().decode("utf-8", "replace")
            seq = "".join(ln for ln in txt.splitlines() if ln and not ln.startswith(">"))
            seq = "".join(c for c in seq.upper() if c in AA1)
            cache[acc] = seq or None
            return cache[acc]
        except Exception:
            time.sleep(1.5)
    cache[acc] = None
    return None


def write_boltz_yaml(job: dict, path: Path):
    rec = job["receptor_seq"]
    pep = job["peptide_seq"]
    lines = ["version: 1", "sequences:",
             "  - protein:", "      id: A", f"      sequence: {rec}", "      msa: empty",
             "  - protein:", "      id: B", f"      sequence: {pep}", "      cyclic: true", "      msa: empty"]
    path.write_text("\n".join(lines) + "\n")


def run_boltz(yaml_path: Path, out_dir: Path, msa_server: bool, timeout_s: int):
    """Invoke the stock `boltz predict`. Returns (rc, stdout_tail)."""
    cmd = ["boltz", "predict", str(yaml_path),
           "--out_dir", str(out_dir),
           "--output_format", "pdb",
           "--accelerator", "gpu", "--devices", "1"]
    if msa_server:
        cmd += ["--use_msa_server"]
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout_s)
        return p.returncode, (p.stdout[-1500:] + p.stderr[-1500:])
    except subprocess.TimeoutExpired:
        return 124, "boltz predict TIMEOUT"


def _find(out_dir: Path, patterns):
    for pat in patterns:
        hits = sorted(out_dir.rglob(pat))
        if hits:
            return hits[0]
    return None


def parse_confidence(pred_root: Path):
    """Boltz writes confidence_*.json under boltz_results_*/predictions/<name>/. Return dict with iptm/plddt/ptm."""
    cj = _find(pred_root, ["confidence_*_model_0.json", "confidence*.json"])
    if cj is None:
        return None
    try:
        d = json.loads(cj.read_text())
    except Exception:
        return None
    # Boltz keys: 'confidence_score','ptm','iptm','complex_plddt','complex_iplddt','ligand_iptm','protein_iptm',...
    return {
        "iptm": d.get("iptm", d.get("protein_iptm")),
        "ptm": d.get("ptm"),
        "complex_plddt": d.get("complex_plddt", d.get("plddt")),
        "confidence_score": d.get("confidence_score"),
        "raw": {k: d.get(k) for k in ("iptm", "ptm", "complex_plddt", "confidence_score", "ligand_iptm")},
    }


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--jobs", required=True, help="jobs_canonical.jsonl from d2_augment_prep.py")
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--min-iptm", type=float, default=0.6, help="interface-ipTM confidence gate")
    ap.add_argument("--min-plddt", type=float, default=0.7, help="complex-pLDDT confidence gate")
    ap.add_argument("--msa-server", action="store_true", help="use ColabFold MSA server (needs network); default off")
    ap.add_argument("--per-job-timeout", type=int, default=1800, help="seconds per Boltz prediction")
    ap.add_argument("--limit", type=int, default=0, help="cap #jobs (0 = all)")
    ap.add_argument("--resolve-missing-receptor", action="store_true",
                    help="if a job has receptor_seq=null, fetch it from UniProt here (prep was run offline)")
    args = ap.parse_args(argv)

    out = Path(args.out_dir)
    (out / "predicted").mkdir(parents=True, exist_ok=True)
    (out / "_yaml").mkdir(parents=True, exist_ok=True)
    (out / "_boltz").mkdir(parents=True, exist_ok=True)
    man_path = out / "predictions_manifest.jsonl"

    # resume-aware: skip job_ids already in the manifest
    done = set()
    if man_path.is_file():
        for ln in man_path.read_text().splitlines():
            if ln.strip():
                try:
                    done.add(json.loads(ln)["job_id"])
                except Exception:
                    pass

    jobs = []
    for ln in Path(args.jobs).read_text().splitlines():
        if ln.strip():
            jobs.append(json.loads(ln))
    if args.limit:
        jobs = jobs[: args.limit]

    cache: dict = {}
    n_kept = n_gated = n_failed = 0
    with open(man_path, "a") as man:
        for i, job in enumerate(jobs, 1):
            jid = job["job_id"]
            if jid in done:
                continue
            rec = job.get("receptor_seq")
            if not rec and args.resolve_missing_receptor:
                rec = fetch_uniprot_seq(job["uniprot"], cache)
                job["receptor_seq"] = rec
            if not rec:
                rec_row = {"job_id": jid, "status": "no_receptor_seq", "kept": False,
                           "conformer_provenance": job["conformer_provenance"], "train_only": True}
                man.write(json.dumps(rec_row) + "\n"); man.flush()
                n_failed += 1
                continue

            yaml_path = out / "_yaml" / f"{jid}.yaml"
            write_boltz_yaml(job, yaml_path)
            job_boltz_out = out / "_boltz" / jid
            rc, tail = run_boltz(yaml_path, job_boltz_out, args.msa_server, args.per_job_timeout)

            conf = parse_confidence(job_boltz_out) if rc == 0 else None
            pdb = _find(job_boltz_out, ["*_model_0.pdb", "*model_0.pdb", "*.pdb"]) if rc == 0 else None

            row = {
                "job_id": jid,
                "peptide_seq": job["peptide_seq"],
                "cyclic_type": job.get("cyclic_type"),
                "uniprot": job["uniprot"],
                "target_name": job.get("target_name"),
                "affinity_nM": job.get("affinity_nM"),
                "tool": job["tool"],
                "conformer_provenance": job["conformer_provenance"],
                "train_only": True,
                "boltz_rc": rc,
                "confidence": conf,
            }

            if rc != 0 or conf is None or pdb is None:
                row["status"] = "predict_failed"
                row["kept"] = False
                row["detail"] = tail[-400:]
                n_failed += 1
                man.write(json.dumps(row) + "\n"); man.flush()
                continue

            iptm = conf.get("iptm")
            plddt = conf.get("complex_plddt")
            pass_gate = (iptm is not None and plddt is not None
                         and iptm >= args.min_iptm and plddt >= args.min_plddt)
            row["gate"] = {"min_iptm": args.min_iptm, "min_plddt": args.min_plddt,
                           "iptm": iptm, "complex_plddt": plddt, "pass": bool(pass_gate)}

            if pass_gate:
                dst = out / "predicted" / jid
                dst.mkdir(parents=True, exist_ok=True)
                (dst / "complex.pdb").write_text(Path(pdb).read_text())
                (dst / "confidence.json").write_text(json.dumps(conf, indent=2))
                (dst / "job.json").write_text(json.dumps(job, indent=2))
                row["status"] = "kept"
                row["kept"] = True
                row["complex_pdb"] = str(dst / "complex.pdb")
                n_kept += 1
            else:
                row["status"] = "gated_out"
                row["kept"] = False
                n_gated += 1

            man.write(json.dumps(row) + "\n"); man.flush()
            if i % 10 == 0:
                print(f"[predict] {i}/{len(jobs)} : {n_kept} kept, {n_gated} gated, {n_failed} failed", flush=True)

    summary = {
        "experiment": "D2 (2ii) Boltz prediction of bound cyclic complexes for augmentation",
        "jobs_file": os.path.abspath(args.jobs),
        "out_dir": os.path.abspath(args.out_dir),
        "n_jobs": len(jobs),
        "n_kept": n_kept,
        "n_gated_out": n_gated,
        "n_failed": n_failed,
        "gate": {"min_iptm": args.min_iptm, "min_plddt": args.min_plddt},
        "provenance": "predicted (train-only)",
        "note": ("Every kept complex is conformer_provenance=<tool>_predicted, train_only=True. Confidence-gated on "
                 "ipTM(interface)+complex_plddt. Feed <out-dir>/predicted + predictions_manifest.jsonl to "
                 "d2_augment_integrate.py."),
    }
    (out / "predict_summary.json").write_text(json.dumps(summary, indent=2))
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
