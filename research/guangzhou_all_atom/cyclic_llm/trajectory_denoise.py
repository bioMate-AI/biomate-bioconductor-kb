"""Use the display LONGITUDINAL round trajectory (R2..R6) — collected but unused (v2/v3/selector
collapsed it to terminal log2fc). A true binder enriches MONOTONICALLY across rounds; a late single-
round spike is a PCR/amplification JACKPOT artifact that still passes the log2fc>=2 binder rule. This
reconstructs each peptide's per-round count vector and splits is_binder into CLEAN vs JACKPOT, so the
selector's positive set can be denoised. Per target it reports the clean/jackpot breakdown + trajectory
features (slope, monotonicity) — the signal we were throwing away.
"""
from __future__ import annotations
import argparse, gzip, csv, json
from collections import defaultdict
import numpy as np

AA = "ACDEFGHIKLMNPQRSTVWY"
ROUNDS = ["R2", "R3", "R4", "R5", "R6"]
RIDX = {r: i for i, r in enumerate(ROUNDS)}


def load_trajectories(csv_gz, target):
    """(seq) -> {counts:[c_R2..c_R6], enr, is_binder}. Missing rounds => 0 count."""
    traj = defaultdict(lambda: {"counts": [0.0] * len(ROUNDS), "enr": None, "is_binder": False})
    with gzip.open(csv_gz, "rt") as f:
        hdr = f.readline().rstrip("\n").split(","); ix = {c: i for i, c in enumerate(hdr)}
        for line in f:
            p = line.rstrip("\n").split(",")
            if p[ix["target"]].split(" ")[0] != target: continue
            seq = p[ix["sequence"]].strip().upper()
            if not seq or any(c not in AA for c in seq) or not (6 <= len(seq) <= 14): continue
            rd = p[ix["round_or_io"]].strip()
            if rd not in RIDX: continue
            try: cnt = float(p[ix["count"]])
            except ValueError: cnt = 0.0
            t = traj[seq]; t["counts"][RIDX[rd]] += cnt
            try: t["enr"] = max(t["enr"] if t["enr"] is not None else -1e9, float(p[ix["enrichment_log2fc"]]))
            except ValueError: pass
            if p[ix["is_binder"]] in ("1", "True", "true"): t["is_binder"] = True
    return traj


def traj_features(counts):
    """slope of log1p(count) vs round index + monotonicity fraction (non-decreasing consecutive pairs)."""
    y = np.log1p(np.array(counts, float))
    x = np.arange(len(y), dtype=float)
    # only fit over rounds where the peptide is present at all (count>0 somewhere)
    if y.max() <= 0: return {"slope": 0.0, "monotonic_frac": 0.0, "peak_round": -1}
    slope = float(np.polyfit(x, y, 1)[0])
    diffs = np.diff(y)
    mono = float((diffs >= -1e-9).mean())          # fraction of consecutive rounds non-decreasing
    peak = int(np.argmax(y))
    return {"slope": round(slope, 4), "monotonic_frac": round(mono, 3), "peak_round": peak}


def run(args):
    traj = load_trajectories(args.csv, args.target)
    recs = []
    for seq, t in traj.items():
        feats = traj_features(t["counts"])
        recs.append({"seq": seq, "is_binder": t["is_binder"], "enr": t["enr"], **feats,
                     "counts": [int(c) for c in t["counts"]]})
    binders = [r for r in recs if r["is_binder"]]
    # CLEAN binder = monotonic enrichment into the final rounds (real selection), not a mid-round jackpot
    def is_clean(r):
        return r["slope"] > 0 and r["monotonic_frac"] >= args.mono_thresh and r["peak_round"] >= len(ROUNDS) - 2
    clean = [r for r in binders if is_clean(r)]
    jackpot = [r for r in binders if not is_clean(r)]
    out = {
        "target": args.target, "n_peptides": len(recs), "n_binders": len(binders),
        "n_clean_binders": len(clean), "n_jackpot_binders": len(jackpot),
        "clean_frac_of_binders": round(len(clean) / max(1, len(binders)), 3),
        "mono_thresh": args.mono_thresh,
        "clean_mean_slope": round(float(np.mean([r["slope"] for r in clean])), 3) if clean else None,
        "jackpot_mean_slope": round(float(np.mean([r["slope"] for r in jackpot])), 3) if jackpot else None,
        "clean_mean_monotonic": round(float(np.mean([r["monotonic_frac"] for r in clean])), 3) if clean else None,
        "jackpot_mean_monotonic": round(float(np.mean([r["monotonic_frac"] for r in jackpot])), 3) if jackpot else None,
        "example_clean": [r["seq"] for r in sorted(clean, key=lambda r: -r["slope"])[:3]],
        "example_jackpot": [{"seq": r["seq"], "counts": r["counts"]} for r in jackpot[:3]],
        "note": "CLEAN = monotonic enrichment peaking in final rounds (real binder); JACKPOT = passes "
                "log2fc>=2 but non-monotonic/mid-round spike (likely PCR/amplification artifact). The "
                "longitudinal trajectory (R2..R6 counts) was collected but collapsed to terminal log2fc "
                "by v2/v3/selector; this recovers it to DENOISE the binder positive set.",
    }
    print("TRAJ", json.dumps(out))
    if args.out:
        from pathlib import Path
        Path(args.out).parent.mkdir(parents=True, exist_ok=True)
        # also dump the clean-binder seq set for the selector to use as denoised positives
        json.dump({"summary": out, "clean_binder_seqs": [r["seq"] for r in clean],
                   "jackpot_binder_seqs": [r["seq"] for r in jackpot]}, open(args.out, "w"), indent=2)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv", required=True); ap.add_argument("--target", required=True)
    ap.add_argument("--mono-thresh", type=float, default=0.75); ap.add_argument("--out")
    run(ap.parse_args())


if __name__ == "__main__":
    main()
