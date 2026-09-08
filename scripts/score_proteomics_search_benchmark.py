#!/usr/bin/env python3
"""
score_proteomics_search_benchmark.py — BioMate proteomics DB-search benchmark scorer

Consumes NORMALIZED per-method PSM tables and computes the two benchmark axes on
the SAME runs, plus the calibration (honesty) axis:

  * MATCH-COUNT  : #PSMs / #peptides / #proteins at a claimed target-decoy FDR (1%)
  * CALIBRATION  : measured entrapment false-match-rate (FMR) at the claimed FDR
  * SPEED        : passed through from the Nextflow executor trace (never self-report)
  * (Phase 1)    : precision/recall + recall@k vs a synthetic ground-truth peptide set

The scorer is engine-agnostic: every engine's native output (Comet pepXML,
MS-GF+ mzIdentML, ...) is first normalized to ONE schema by normalize_psms.py,
so this module never parses engine formats.

Design: docs/20260907_PROTEOMICS_DB_SEARCH_OPTIMIZATION_SURVEY.md §14

Normalized PSM table schema (TSV/parquet), one row per PSM:
    spectrum_id   str    unique spectrum key (file:scan)
    peptide       str    peptide sequence (with mods), for peptide-level dedup
    protein       str    protein/accession the peptide maps to
    score         float  engine score; HIGHER = better (normalize sign upstream)
    label         str    one of: target | decoy | entrapment
                         - target     : sequence from the real proteome
                         - entrapment : sequence from the entrapment DB (known-false)
                         - decoy      : reversed/shuffled sequence (for target-decoy FDR)
    is_synthetic_true  bool  (optional; Phase 1) true if peptide ∈ synthetic ground-truth set

FDR / q-value method (target-decoy, standard):
    Rank PSMs by score desc. At each threshold, FDR = #decoy_above / #target_above.
    q-value = min FDR over all thresholds at-or-below (monotone from the bottom).
    "target" for the target-decoy calc = {target ∪ entrapment} (both are non-decoy
    forward hits); entrapment IDs are then counted separately for the FMR estimate.

Entrapment FMR estimator (combined; Wen 2025; Freestone/Keich/Noble):
    Among accepted (q<=claimed) forward PSMs, let
        E = # entrapment IDs, T = # true-target IDs, ratio = |entrapment_db|/|target_db|
    Estimated actual false-discovery proportion among target IDs:
        FMR ≈ (E / ratio) / T
    A calibrated method has measured FMR ≈ claimed FDR. FMR >> claimed => FDR inflation.
    (Set --paired for the paired estimator when normalized tables carry pairing info.)

Usage:
    python scripts/score_proteomics_search_benchmark.py \
        --psms results/PXD000612/comet.psms.tsv results/PXD000612/msgf.psms.tsv \
        --trace results/PXD000612/nextflow_trace.txt \
        --entrapment-ratio 1.0 --claimed-fdr 0.01 \
        --out evaluation/results/proteomics_search_benchmark_v1/PXD000612/

Outputs:
    metrics.json          per-method: ids@fdr (psm/peptide/protein), measured FMR, speed
    calibration.tsv       claimed-FDR sweep vs measured-FMR (the calibration curve)
    pareto.tsv            speed vs entrapment-clean IDs (the headline frontier)

Run as pure Python (no engine deps): stdlib + optional pandas. Testable standalone
(`--selftest` runs a synthetic-data unit check and exits).
"""
from __future__ import annotations
import argparse
import csv
import json
import math
import os
import sys
from dataclasses import dataclass, field, asdict


# ----------------------------------------------------------------------------- I/O
def read_psms(path):
    """Read a normalized PSM TSV -> list of dict rows. Minimal, dependency-free."""
    rows = []
    with open(path, newline="") as fh:
        rdr = csv.DictReader(fh, delimiter="\t")
        for r in rdr:
            r["score"] = float(r["score"])
            r["label"] = r["label"].strip().lower()
            if r["label"] not in ("target", "decoy", "entrapment"):
                raise ValueError(f"{path}: bad label {r['label']!r} "
                                 "(expected target|decoy|entrapment)")
            rows.append(r)
    if not rows:
        raise ValueError(f"{path}: no PSM rows")
    return rows


# ----------------------------------------------------------------- q-values (TD)
def assign_qvalues(psms):
    """
    Target-decoy q-values. Forward = {target, entrapment}; decoys estimate the null.
    Returns psms with an added 'qvalue' key. Higher score = better.

    FDR(t) = #decoys with score>=t / max(1, #forwards with score>=t)
    q(psm)  = min over thresholds at-or-below psm's score  (monotone non-increasing
              as score increases). Standard Kall/Storey target-decoy estimator.
    """
    # Sort by score descending; stable so ties keep input order.
    order = sorted(range(len(psms)), key=lambda i: psms[i]["score"], reverse=True)
    n_decoy = 0
    n_fwd = 0
    running = []  # (idx, raw_fdr) in score-desc order
    for i in order:
        if psms[i]["label"] == "decoy":
            n_decoy += 1
        else:
            n_fwd += 1
        raw_fdr = n_decoy / n_fwd if n_fwd else 0.0
        running.append((i, raw_fdr))
    # Monotonize from the bottom (worst score) up: q = min raw_fdr seen so far.
    min_so_far = math.inf
    q = {}
    for i, raw_fdr in reversed(running):
        min_so_far = min(min_so_far, raw_fdr)
        q[i] = min_so_far
    for i in range(len(psms)):
        psms[i]["qvalue"] = q[i]
    return psms


# --------------------------------------------------------------------- counting
def _accepted_forwards(psms, claimed_fdr):
    """Forward (non-decoy) PSMs at q <= claimed_fdr."""
    return [p for p in psms if p["label"] != "decoy" and p["qvalue"] <= claimed_fdr]


def count_ids(psms, claimed_fdr):
    """#PSMs, #peptides, #proteins among accepted TRUE-TARGET forwards (exclude entrapment)."""
    acc = [p for p in _accepted_forwards(psms, claimed_fdr) if p["label"] == "target"]
    peptides = {p["peptide"] for p in acc}
    proteins = {p["protein"] for p in acc}
    return {"psms": len(acc), "peptides": len(peptides), "proteins": len(proteins)}


def entrapment_fmr(psms, claimed_fdr, ratio):
    """
    Combined-entrapment estimate of the ACTUAL false-match rate among target IDs.
    FMR ≈ (E / ratio) / T. Returns dict with E, T, ratio, fmr.
    """
    acc = _accepted_forwards(psms, claimed_fdr)
    E = sum(1 for p in acc if p["label"] == "entrapment")
    T = sum(1 for p in acc if p["label"] == "target")
    fmr = (E / ratio) / T if T > 0 else float("nan")
    return {"entrapment_ids": E, "target_ids": T, "ratio": ratio, "fmr": fmr}


def calibration_curve(psms, ratio, grid=None):
    """Sweep claimed FDR and report measured FMR at each — the calibration curve."""
    if grid is None:
        grid = [0.001, 0.002, 0.005, 0.01, 0.02, 0.05]
    out = []
    for f in grid:
        e = entrapment_fmr(psms, f, ratio)
        out.append({"claimed_fdr": f, "measured_fmr": e["fmr"],
                    "target_ids": e["target_ids"], "entrapment_ids": e["entrapment_ids"]})
    return out


# --------------------------------------------------------------- speed (trace)
def parse_nextflow_trace(path):
    """
    Pull per-process wall-clock/CPU/RAM from a Nextflow trace.txt. Best-effort:
    returns {process_name: {realtime_s, cpu_pct, peak_rss_mb}}. Speed is always
    read from the executor, never a tool's self-reported log (§14.4).
    """
    if not path or not os.path.exists(path):
        return {}
    def to_seconds(s):
        s = s.strip()
        if s in ("-", ""):
            return None
        # forms: "1h 2m 3s" | "12m 30s" | "45s" | "1.2s" | "123 ms"
        total = 0.0
        if "ms" in s:
            try: return float(s.replace("ms", "").strip()) / 1000.0
            except ValueError: return None
        for tok in s.split():
            try:
                if tok.endswith("h"): total += float(tok[:-1]) * 3600
                elif tok.endswith("m"): total += float(tok[:-1]) * 60
                elif tok.endswith("s"): total += float(tok[:-1])
            except ValueError:
                pass
        return total or None
    def to_mb(s):
        s = s.strip()
        if s in ("-", ""): return None
        try:
            if s.upper().endswith("GB"): return float(s[:-2]) * 1024
            if s.upper().endswith("MB"): return float(s[:-2])
            if s.upper().endswith("KB"): return float(s[:-2]) / 1024
        except ValueError:
            return None
        return None
    res = {}
    with open(path, newline="") as fh:
        rdr = csv.DictReader(fh, delimiter="\t")
        for row in rdr:
            name = row.get("name") or row.get("process") or ""
            res[name] = {
                "realtime_s": to_seconds(row.get("realtime", "")),
                "cpu_pct": (row.get("%cpu") or "").rstrip("%") or None,
                "peak_rss_mb": to_mb(row.get("peak_rss", "")),
            }
    return res


# ------------------------------------------------------------------- top-level
def score_method(psm_path, claimed_fdr, ratio, trace=None, method_id=None):
    psms = read_psms(psm_path)
    assign_qvalues(psms)
    ids = count_ids(psms, claimed_fdr)
    fmr = entrapment_fmr(psms, claimed_fdr, ratio)
    calib = calibration_curve(psms, ratio)
    speed = {}
    if trace:
        tr = parse_nextflow_trace(trace)
        # crude: sum realtime across processes whose name contains the method id
        rts = [v["realtime_s"] for k, v in tr.items()
               if v["realtime_s"] and (not method_id or method_id.lower() in k.lower())]
        speed = {"wall_clock_s": round(sum(rts), 2) if rts else None,
                 "psms_per_cpu_sec": (round(ids["psms"] / sum(rts), 2)
                                      if rts and sum(rts) > 0 else None)}
    return {
        "method": method_id or os.path.basename(psm_path),
        "claimed_fdr": claimed_fdr,
        "ids_at_fdr": ids,
        "calibration": fmr,
        "calibration_curve": calib,
        "speed": speed,
        "calibrated": (not math.isnan(fmr["fmr"])) and fmr["fmr"] <= claimed_fdr * 1.3,
    }


def write_outputs(results, outdir):
    os.makedirs(outdir, exist_ok=True)
    with open(os.path.join(outdir, "metrics.json"), "w") as fh:
        json.dump(results, fh, indent=2)
    # calibration.tsv (long form across methods)
    with open(os.path.join(outdir, "calibration.tsv"), "w", newline="") as fh:
        w = csv.writer(fh, delimiter="\t")
        w.writerow(["method", "claimed_fdr", "measured_fmr", "target_ids", "entrapment_ids"])
        for r in results:
            for c in r["calibration_curve"]:
                w.writerow([r["method"], c["claimed_fdr"],
                            f"{c['measured_fmr']:.4f}" if c["measured_fmr"] == c["measured_fmr"] else "nan",
                            c["target_ids"], c["entrapment_ids"]])
    # pareto.tsv: speed vs entrapment-clean IDs (headline frontier)
    with open(os.path.join(outdir, "pareto.tsv"), "w", newline="") as fh:
        w = csv.writer(fh, delimiter="\t")
        w.writerow(["method", "wall_clock_s", "peptides_at_1pct", "measured_fmr", "calibrated"])
        for r in results:
            w.writerow([r["method"], r["speed"].get("wall_clock_s"),
                        r["ids_at_fdr"]["peptides"], f"{r['calibration']['fmr']:.4f}"
                        if r["calibration"]["fmr"] == r["calibration"]["fmr"] else "nan",
                        r["calibrated"]])


# ------------------------------------------------------------------- self-test
def _selftest():
    """Synthetic PSM table with known structure -> assert the estimators are sane."""
    import tempfile
    # 100 clean high-scoring targets; then decoys (2.0..1.6); then entrapment
    # CLEARLY BELOW all decoys (1.5..1.1) so at 1% FDR none leak in (calibrated case).
    # (If entrapment scored *among* the decoys, the scorer would correctly report a
    #  raised FMR — that is the miscalibration the benchmark is designed to catch.)
    rows = [("spectrum_id", "peptide", "protein", "score", "label")]
    for i in range(100):
        rows.append((f"f:{i}", f"PEPTIDEK{i}", f"PROT{i%20}", f"{10.0 - i*0.01}", "target"))
    for i in range(5):
        rows.append((f"d:{i}", f"DECOYPEP{i}", f"DEC{i}", f"{2.0 - i*0.1}", "decoy"))
    for i in range(5):
        rows.append((f"e:{i}", f"ENTRAPEP{i}", f"ENT{i}", f"{1.5 - i*0.1}", "entrapment"))
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, "t.tsv")
        with open(p, "w", newline="") as fh:
            csv.writer(fh, delimiter="\t").writerows(rows)
        r = score_method(p, claimed_fdr=0.01, ratio=1.0, method_id="selftest")
        # At 1% FDR all 100 clean targets are accepted; decoys+entrapment sit at
        # high q so are excluded -> FMR ~ 0, calibrated True.
        assert r["ids_at_fdr"]["psms"] == 100, r["ids_at_fdr"]
        assert r["ids_at_fdr"]["proteins"] == 20, r["ids_at_fdr"]
        assert r["calibration"]["entrapment_ids"] == 0, r["calibration"]
        assert r["calibration"]["fmr"] == 0.0, r["calibration"]
        assert r["calibrated"] is True
        # Loosen FDR to include the junk -> entrapment IDs must rise (miscalibration detectable).
        loose = score_method(p, claimed_fdr=0.20, ratio=1.0, method_id="selftest")
        assert loose["calibration"]["entrapment_ids"] > r["calibration"]["entrapment_ids"], \
            loose["calibration"]
    print("selftest OK: q-values, ID counts, and entrapment-FMR estimator behave correctly")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--psms", nargs="+", help="normalized PSM TSVs (one per method)")
    ap.add_argument("--method-ids", nargs="*", default=None,
                    help="labels for each --psms file (default: filename)")
    ap.add_argument("--trace", default=None, help="Nextflow trace.txt for speed")
    ap.add_argument("--claimed-fdr", type=float, default=0.01)
    ap.add_argument("--entrapment-ratio", type=float, default=1.0)
    ap.add_argument("--out", default="evaluation/results/proteomics_search_benchmark_v1/")
    ap.add_argument("--selftest", action="store_true", help="run synthetic unit check and exit")
    args = ap.parse_args(argv)

    if args.selftest:
        _selftest()
        return 0
    if not args.psms:
        ap.error("--psms is required (or use --selftest)")

    ids = args.method_ids or [None] * len(args.psms)
    results = [score_method(p, args.claimed_fdr, args.entrapment_ratio,
                            trace=args.trace, method_id=mid)
               for p, mid in zip(args.psms, ids)]
    write_outputs(results, args.out)
    for r in results:
        print(f"{r['method']:>12}  peptides@{args.claimed_fdr:.0%}="
              f"{r['ids_at_fdr']['peptides']:>7}  proteins={r['ids_at_fdr']['proteins']:>6}  "
              f"FMR={r['calibration']['fmr']:.4f}  calibrated={r['calibrated']}")
    print(f"\nwrote metrics.json / calibration.tsv / pareto.tsv -> {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
