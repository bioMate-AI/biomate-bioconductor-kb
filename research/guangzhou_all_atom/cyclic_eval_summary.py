#!/usr/bin/env python3
"""Extended cyclic co-design eval summary: oracle best-of-N + realistic pick-1 + sequence-disjoint
sensitivity, for base vs fine-tuned UniMoMo on the PepBDB-cyclic test. Reads UniMoMo's own per-target
metric records (no re-run): either the `eval_report_.jsonl` written by scripts.metrics.peptide, or the
`Finished N/M, {record}` lines in its stdout log (eval_<label>.log). Each record carries
DockQ={'max' (oracle best-of-N), 'max*' (flow-likelihood-selected = realistic pick-1), 'individual', ...}.

Aggregation: mean over targets of the per-target value (matches UniMoMo's eval_final log).
Receptor-disjoint sensitivity excludes the test complexes whose RECEPTOR sequence also appears in train
(from split_audit.json); the test is already peptide- and complex-disjoint, so this isolates the only
residual leakage. Designability (self-consistency scRMSD) is NOT computed here — it needs an independent
folder (ESMFold/Boltz) not in the UniMoMo env; see --designability note.

Usage:
  cyclic_eval_summary.py --base eval_base.log --ft eval_ft.log --out ft_eval_summary.json
  cyclic_eval_summary.py --base results/base/eval_report_.jsonl --ft results/ft/eval_report_.jsonl --out ...
  cyclic_eval_summary.py --selftest
"""
import argparse, ast, json, re, sys

# Receptor-overlap test complexes (receptor seq shared with train; peptide+complex already disjoint).
# Source: results/unimomo-cyclic-ft-20261003T170124Z/SIMULATED_dpo_integration/split_audit.json (train_vs_test).
RECEPTOR_OVERLAP_PREFIXES = {"4kel", "5iop", "5t1m", "5t90", "5th2"}

def _pid(_id): return str(_id).split("_")[0].lower()

def load_records(path):
    """Return {id: record}. Accepts eval_report_.jsonl (one JSON/line) or an eval log with
    'Finished N/M, {python-dict-repr}' lines."""
    recs = {}
    for ln in open(path):
        ln = ln.rstrip("\n")
        d = None
        if "Finished " in ln and "{" in ln:            # stdout log: python dict repr
            frag = ln[ln.find(", ", ln.find("Finished ")) + 2:].strip()
            try: d = ast.literal_eval(frag)
            except Exception: d = None
        elif ln.strip().startswith("{"):               # eval_report_.jsonl: JSON
            try: d = json.loads(ln)
            except Exception: d = None
        if isinstance(d, dict) and "id" in d:
            recs[d["id"]] = d
    return recs

def _mean(xs): return round(sum(xs) / len(xs), 4) if xs else None

def summarize_one(recs):
    def agg(metric, key, disjoint=False):
        vals = []
        for _id, d in recs.items():
            if disjoint and _pid(_id) in RECEPTOR_OVERLAP_PREFIXES: continue
            m = d.get(metric)
            if isinstance(m, dict) and m.get(key) is not None: vals.append(m[key])
        return _mean(vals), len(vals)
    o, n = agg("DockQ", "max")
    p, _ = agg("DockQ", "max*")
    od, nd = agg("DockQ", "max", disjoint=True)
    pd, _ = agg("DockQ", "max*", disjoint=True)
    aar, _ = agg("AAR", "max")
    return {"n_targets": len(recs),
            "dockq_oracle": o, "dockq_pick1": p,
            "dockq_oracle_receptor_disjoint": od, "dockq_pick1_receptor_disjoint": pd,
            "n_receptor_disjoint": nd, "aar_oracle": aar,
            "designability_scRMSD": None, "frac_designable": None,
            "designability_note": "requires independent folder (ESMFold/Boltz) not in UniMoMo env; run separately"}

def build(base_path, ft_path):
    base, ft = summarize_one(load_records(base_path)), summarize_one(load_records(ft_path))
    def delta(k): return None if (base[k] is None or ft[k] is None) else round(ft[k] - base[k], 4)
    return {
        "benchmark": "PepBDB-cyclic test (UniMoMo pepbench harness), cyclic co-design",
        "test_split": "peptide-disjoint + complex-disjoint; receptor-disjoint subset excludes "
                      + ",".join(sorted(RECEPTOR_OVERLAP_PREFIXES)),
        "aggregation": "mean over targets; oracle=per-target max over candidates; pick1=per-target max* (flow-likelihood selected)",
        "base": base, "ft": ft,
        "delta_ft_minus_base": {k: delta(k) for k in
            ("dockq_oracle", "dockq_pick1", "dockq_oracle_receptor_disjoint",
             "dockq_pick1_receptor_disjoint", "aar_oracle")},
    }

def _selftest():
    # synthetic: 3 targets, one (4kel) is receptor-overlap. ft improves pick-1 more than oracle.
    def rec(i, dmax, dstar, aar=0.3):
        return f"2026::INFO::Finished {i}/3, " + repr(
            {"id": i, "AAR": {"max": aar, "max*": aar}, "DockQ": {"max": dmax, "max*": dstar, "individual": [dstar, dmax]}})
    import tempfile, os
    def wf(rows):
        f = tempfile.NamedTemporaryFile("w", suffix=".log", delete=False); f.write("\n".join(rows) + "\n"); f.close(); return f.name
    base = wf([rec("1abc", 0.40, 0.20), rec("2xyz", 0.50, 0.25), rec("4kel", 0.90, 0.90)])
    ft   = wf([rec("1abc", 0.44, 0.26), rec("2xyz", 0.52, 0.31), rec("4kel", 0.90, 0.90)])
    s = build(base, ft); os.unlink(base); os.unlink(ft)
    checks = {
        "base loaded 3 targets": s["base"]["n_targets"] == 3,
        "oracle = mean of max (base=0.6)": s["base"]["dockq_oracle"] == round((0.40+0.50+0.90)/3, 4),
        "pick1 = mean of max* (base=0.45)": s["base"]["dockq_pick1"] == round((0.20+0.25+0.90)/3, 4),
        "receptor-disjoint drops 4kel (n=2)": s["base"]["n_receptor_disjoint"] == 2,
        "disjoint oracle base = mean(0.40,0.50)=0.45": s["base"]["dockq_oracle_receptor_disjoint"] == 0.45,
        "pick1 delta (+) computed": s["delta_ft_minus_base"]["dockq_pick1"] is not None and s["delta_ft_minus_base"]["dockq_pick1"] > 0,
        "disjoint isolates ft gain (excl. the tied 4kel)": s["delta_ft_minus_base"]["dockq_oracle_receptor_disjoint"] > s["delta_ft_minus_base"]["dockq_oracle"],
    }
    for k, v in checks.items(): print(f"  {'PASS' if v else 'FAIL'}  {k}")
    ok = all(checks.values()); print("ALL_CHECKS_PASS=" + str(ok)); return 0 if ok else 1

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--base"); ap.add_argument("--ft"); ap.add_argument("--out")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest: sys.exit(_selftest())
    if not (a.base and a.ft and a.out): ap.error("need --base --ft --out (or --selftest)")
    s = build(a.base, a.ft)
    open(a.out, "w").write(json.dumps(s, indent=2))
    print(json.dumps(s, indent=2))
