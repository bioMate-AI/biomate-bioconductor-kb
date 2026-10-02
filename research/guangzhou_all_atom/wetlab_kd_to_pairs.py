#!/usr/bin/env python3
"""Closed-loop TEST->LEARN link: wet-lab KD results (CRO SPR) -> EXPERT preference pairs.

This is the seam that makes the DBTL loop real: a CRO round returns measured KD per peptide; this
converts that into (chosen >- rejected) EXPERT-stream pairs (stronger binder >- weaker/non-binder,
within a target), through the SAME dpo_pairs schema the DPO close-back trains on
(dpo_peptide_trainer.py / dpo_unimomo_adapter.py). It does NOT train — it emits the versioned,
provenance-tagged PairSet that the trainer consumes.

Pairing policy (within each target/prompt):
  * measured binder (lower KD) >- measured weaker binder, when they differ by >= MARGIN_STRONG (log10);
    pairs with a smaller gap are emitted but marked weak=True (drop with --drop_weak).
  * any measured binder >- non-binder (no measurable KD) — always a confident pair.
  * never pair two peptides within noise of each other (gap < MARGIN_MIN) — dropped as uninformative.

Input CSV columns (case-insensitive; extras ignored):
  id (or item/peptide_id) , seq (or sequence) , target , kd_nM   (blank / "no binding" / "nb" = non-binder)

Usage:
  python wetlab_kd_to_pairs.py --kd round1_kd.csv --out pairs.jsonl --trl_out pairs_trl.jsonl [--drop_weak]
  python wetlab_kd_to_pairs.py --selftest
"""
import argparse, csv, sys, math, itertools, tempfile, os
from dpo_pairs import ExemplarPair, emit_pairs

MARGIN_MIN = 0.3      # log10(KD ratio) below this = within noise -> no pair (≈ <2x)
MARGIN_STRONG = 0.7   # >= this (≈ >5x) = confident; between MIN and STRONG = weak=True
NONBINDER_TOKENS = {"", "nb", "no binding", "none", "n/a", "na", "nonbinder", "non-binder", ">100000"}

def _parse_kd(v):
    """nM float, or None for a non-binder. Accepts '1200', '1.2uM'(->1200), '>50000'(->nonbinder)."""
    if v is None: return None
    s = str(v).strip().lower()
    if s in NONBINDER_TOKENS: return None
    if s.startswith(">"):      # above the assay ceiling = treat as non-binder for pairing
        return None
    mult = 1.0
    if s.endswith("um") or s.endswith("µm"): mult, s = 1000.0, s[:-2].strip()
    elif s.endswith("nm"): mult, s = 1.0, s[:-2].strip()
    elif s.endswith("mm"): mult, s = 1_000_000.0, s[:-2].strip()
    try: return float(s) * mult
    except ValueError: return None

def _col(row, *names):
    low = {k.lower(): k for k in row}
    for n in names:
        if n in low: return row[low[n]]
    return None

def load_rows(path):
    out = []
    for r in csv.DictReader(open(path)):
        seq = _col(r, "seq", "sequence")
        if not seq: continue
        out.append(dict(
            id=_col(r, "id", "item", "peptide_id") or seq,
            seq=seq.strip().upper(),
            target=(_col(r, "target") or "target").strip(),
            kd=_parse_kd(_col(r, "kd_nm", "kd", "kd_nm_", "kd(nm)")),
        ))
    return out

def exemplars_from_kd(rows):
    """Within each target, build EXPERT ExemplarPairs (stronger binder >- weaker/non-binder)."""
    exemplars = []
    by_t = {}
    for r in rows: by_t.setdefault(r["target"], []).append(r)
    for target, items in by_t.items():
        binders    = [x for x in items if x["kd"] is not None]
        nonbinders = [x for x in items if x["kd"] is None]
        # binder >- non-binder (always confident)
        for b in binders:
            for nb in nonbinders:
                exemplars.append(ExemplarPair(
                    chosen=b["seq"], rejected=nb["seq"], prompt=target,
                    chosen_id=b["id"], rejected_id=nb["id"], source="GenScript_SPR",
                    chosen_provenance="measured_KD", rejected_provenance="measured_nonbinder",
                    reason=f"KD={b['kd']:.1f}nM binder >- non-binder"))
        # binder >- weaker binder (by KD gap)
        for a, b in itertools.combinations(binders, 2):
            strong, weak = (a, b) if a["kd"] <= b["kd"] else (b, a)
            margin = math.log10(weak["kd"] / strong["kd"]) if strong["kd"] > 0 else 0.0
            if margin < MARGIN_MIN:  # within noise -> uninformative
                continue
            exemplars.append(ExemplarPair(
                chosen=strong["seq"], rejected=weak["seq"], prompt=target,
                chosen_id=strong["id"], rejected_id=weak["id"], source="GenScript_SPR",
                chosen_provenance="measured_KD", rejected_provenance="measured_KD",
                margin=round(margin, 3), weak=(margin < MARGIN_STRONG),
                reason=f"KD {strong['kd']:.1f} << {weak['kd']:.1f} nM (Δlog10={margin:.2f})"))
    return exemplars

def build(path, drop_weak=False):
    rows = load_rows(path)
    ex = exemplars_from_kd(rows)
    return emit_pairs(expert_exemplars=ex, drop_weak=drop_weak), rows

def _selftest():
    rows = [
        ("P1","GAYTSKSTGVTF","PD-L1","12"),      # strong 12 nM
        ("P2","SSPFPVFKEFSP","PD-L1","800"),     # mid 800 nM
        ("P3","AAPEVLRKYTSLP","PD-L1","no binding"),  # non-binder
        ("P4","SSNPAAKHIDPM","PD-L1","15"),      # strong 15 nM (~within noise of P1)
        ("Q1","GRGRNKYYP","avb6","50"),          # strong
        ("Q2","NKYRSRRGK","avb6",">100000"),     # ceiling = non-binder
    ]
    with tempfile.NamedTemporaryFile("w", suffix=".csv", delete=False, newline="") as f:
        w = csv.writer(f); w.writerow(["id","seq","target","kd_nM"]); w.writerows(rows); p = f.name
    ps, loaded = build(p); os.unlink(p)
    trl = ps.to_trl_records()
    def has(ch, rj): return any(r["chosen"]==ch and r["rejected"]==rj for r in trl)
    checks = {
        "binder>-nonbinder (P1>-P3)":            has("GAYTSKSTGVTF","AAPEVLRKYTSLP"),
        "binder>-ceiling-nonbinder (Q1>-Q2)":    has("GRGRNKYYP","NKYRSRRGK"),
        "strong>-weak binder (P1>-P2)":          has("GAYTSKSTGVTF","SSPFPVFKEFSP"),
        "P1~P4 within-noise dropped (no pair)":  not (has("GAYTSKSTGVTF","SSNPAAKHIDPM") or has("SSNPAAKHIDPM","GAYTSKSTGVTF")),
        "no symmetric conflicts":                len(ps.dropped_conflicts)==0,
        "direction never reversed (no nonbinder>-binder)": not has("AAPEVLRKYTSLP","GAYTSKSTGVTF"),
    }
    print(f"loaded {len(loaded)} rows -> {len(trl)} TRL pairs; weak-marked={sum(1 for p in ps.pairs if p.weak)}")
    for p in ps.pairs: print(f"  [{p.stream}] {p.chosen_id}>-{p.rejected_id} ({p.prompt})  {p.reason}")
    ok = all(checks.values())
    for k,v in checks.items(): print(f"  {'PASS' if v else 'FAIL'}  {k}")
    print("ALL_CHECKS_PASS=" + str(ok))
    return 0 if ok else 1

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--kd"); ap.add_argument("--out"); ap.add_argument("--trl_out")
    ap.add_argument("--drop_weak", action="store_true"); ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest: sys.exit(_selftest())
    if not (a.kd and a.out): ap.error("need --kd and --out (or --selftest)")
    from pathlib import Path
    ps, rows = build(a.kd, drop_weak=a.drop_weak)
    ps.write_jsonl(Path(a.out))
    if a.trl_out: ps.write_jsonl(Path(a.trl_out), trl_only=True)
    print(f"{len(rows)} KD rows -> {len(ps.pairs)} EXPERT pairs ({sum(1 for p in ps.pairs if p.weak)} weak) -> {a.out}"
          + (f" ; TRL -> {a.trl_out}" if a.trl_out else "")
          + (f" ; {len(ps.dropped_conflicts)} conflicts dropped" if ps.dropped_conflicts else ""))
