#!/usr/bin/env python3
"""Assemble a MULTI-TARGET cyclic-peptide display/selection NGS pool.

Extends the single-target harvester (harvest_display_ngs_rapid.py) to build ONE
unified, target-labeled enrichment table across several distinct targets, so a
target-conditioned LLM can be trained and cross-target generalization tested
(docs/20261005_DISPLAY_NGS_HARVEST.md -> this is the v3 data dependency).

Targets assembled here (all free, public SRA/ENA):
  1. PADI4   (PRJNA1188087)  mRNA-display RaPID covalent, 6 rounds   [REUSED from S3]
  2. hPCSK9  (PRJNA1406026)  XL RaPID, single-round input/output
  3. FIKK13  (PRJNA1172558)  mRNA-display RaPID, 6 rounds
  4. Abeta42 (PRJNA1170358)  M13 phage cyclic (SICLOPPS-style), library->selected
  5. hIAPP   (PRJNA1170358)  M13 phage cyclic (SICLOPPS-style), library->selected

Three parse MODES (each amplicon design reverse-engineered from the deposit):
  * rapid_rounds : CATATG ... (NNK)n ... TGCGGCAGC ; enrichment = log2FC(round vs baseline round)
  * rapid_orf_io : fixed-window ORF from the ATG in CATATG ; enrichment = log2(output/input)
  * phage_io     : CACAAC ...Cys-(var)-Cys... CTCAGT ; enrichment = log2(selected/library)

Enrichment / binder definition (the v2 lesson: bucket by the ENRICHED TAIL, not
quantiles): a peptide is flagged is_binder iff, at its terminal/selected stage,
its count >= --binder-min-count AND its log2FC vs baseline >= --binder-log2fc.
This keys the binder label on the actually-enriched, well-sampled tail rather
than on a distributional quantile that is dominated by noise singletons.

Unified long-table schema (one row per target x sequence x stage):
  target, sequence, n_residues, round_or_io, count, enrichment_log2fc,
  cyclization, display_type, source_accession, is_binder

Usage:
  python3 harvest_display_ngs_multitarget.py \
      --fastq-dir /tmp/mt/fastq --padi4-long /tmp/mt/padi4_long.csv.gz \
      --outdir /tmp/mt/out --name display_ngs_multitarget
"""
import argparse, csv, gzip, json, math, os, sys
from collections import Counter

# ---- standard DNA codon table ----
BASES = "TCAG"
AAS = "FFLLSSSSYY**CC*WLLLLPPPPHHQQRRRRIIIMTTTTNNKKSSRRVVVVAAAADDEEGGGG"
CODON = {a + b + c: AAS[i]
         for i, (a, b, c) in enumerate((x, y, z) for x in BASES for y in BASES for z in BASES)}
COMP = str.maketrans("ACGTN", "TGCAN")


def revcomp(s):
    return s.translate(COMP)[::-1]


def translate(nt):
    return "".join(CODON.get(nt[i:i + 3], "X") for i in range(0, len(nt) - 2, 3))


# ---------- mode: anchor-bounded variable region (rapid_rounds, phage_io) ----------
def extract_anchored(read, up, down, min_cod, max_cod):
    for seq in (read, revcomp(read)):
        i = seq.find(up)
        if i < 0:
            continue
        start = i + len(up)
        j = seq.find(down, start)
        if j < 0:
            continue
        var = seq[start:j]
        if len(var) % 3 != 0:
            continue
        ncod = len(var) // 3
        if not (min_cod <= ncod <= max_cod):
            continue
        if "N" in var:
            continue
        aa = translate(var)
        if "*" in aa or "X" in aa:
            continue
        return aa
    return None


# ---------- mode: fixed-window ORF from the ATG inside CATATG (rapid_orf_io) ----------
def extract_orf_window(read, up, window):
    """Translate a fixed window of `window` codons starting at the ATG that ends
    the `up` anchor (CATATG). Fixed window => stable key despite read truncation."""
    for seq in (read, revcomp(read)):
        i = seq.find(up)
        if i < 0:
            continue
        atg = i + len(up) - 3          # the 'ATG' is the last 3 nt of CATATG
        var = seq[atg:atg + 3 * window]
        if len(var) < 3 * window:
            continue
        if "N" in var:
            continue
        aa = translate(var)
        if "*" in aa or "X" in aa:     # premature stop in window => drop
            continue
        return aa
    return None


def iter_seqs(path):
    with gzip.open(path, "rt") as fh:
        for n, line in enumerate(fh):
            if n % 4 == 1:
                yield line.strip()


def count_sample(path, mode, up, down, min_cod, max_cod, window):
    c = Counter()
    total = productive = 0
    for s in iter_seqs(path):
        total += 1
        if mode == "rapid_orf_io":
            aa = extract_orf_window(s, up, window)
        else:
            aa = extract_anchored(s, up, down, min_cod, max_cod)
        if aa is None:
            continue
        productive += 1
        c[aa] += 1
    return c, total, productive


def log2fc(f, fb, eps):
    return math.log2((f + eps) / (fb + eps))


def process_campaign(cfg, fastq_dir, min_count, binder_min_count, binder_log2fc):
    """Return (rows, summary) for one campaign.
    rows: list of unified dicts; summary: dict for meta."""
    mode = cfg["mode"]
    up = cfg.get("up_anchor", "CATATG")
    down = cfg.get("down_anchor", "TGCGGCAGC")
    min_cod = cfg.get("min_codons", 6)
    max_cod = cfg.get("max_codons", 12)
    window = cfg.get("orf_window", 12)

    # ---- count per stage ----
    # stages: ordered list of (stage_label, [fastq filenames]); baseline stage is stages[0]
    stage_counts = {}
    stage_stats = {}
    for stage_label, files in cfg["stages"]:
        merged = Counter()
        tot = prod = 0
        for fn in files:
            p = os.path.join(fastq_dir, fn)
            if not os.path.exists(p):
                print(f"  !! missing {fn} (skipping)", file=sys.stderr)
                continue
            c, t, pr = count_sample(p, mode, up, down, min_cod, max_cod, window)
            merged.update(c)
            tot += t
            prod += pr
        stage_counts[stage_label] = merged
        stage_stats[stage_label] = {"reads": tot, "productive": prod,
                                    "productive_pct": round(100 * prod / max(tot, 1), 2),
                                    "unique_peptides": len(merged)}
        print(f"  [{cfg['target']}:{stage_label}] reads={tot:,} productive={prod:,} "
              f"({stage_stats[stage_label]['productive_pct']}%) unique={len(merged):,}",
              file=sys.stderr)

    stage_order = [s for s, _ in cfg["stages"]]
    baseline = stage_order[0]
    terminal = stage_order[-1]        # stage used for binder flag (last = most selected)
    totals = {s: sum(c.values()) for s, c in stage_counts.items()}
    pos_totals = [t for t in totals.values() if t]
    if not pos_totals:
        return [], {"target": cfg["target"], "error": "no productive reads"}
    eps = 1.0 / max(1, min(pos_totals))

    # peptides passing min-count floor in any stage
    keep = set()
    for c in stage_counts.values():
        for pep, n in c.items():
            if n >= min_count:
                keep.add(pep)

    def freq(stage, pep):
        t = totals[stage]
        return stage_counts[stage][pep] / t if t else 0.0

    rows = []
    n_binder = 0
    for pep in keep:
        fb = freq(baseline, pep)
        term_fc = log2fc(freq(terminal, pep), fb, eps)
        is_binder = (stage_counts[terminal][pep] >= binder_min_count
                     and term_fc >= binder_log2fc)
        if is_binder:
            n_binder += 1
        for stage in stage_order:
            rows.append({
                "target": cfg["target"],
                "sequence": pep,
                "n_residues": len(pep),
                "round_or_io": stage,
                "count": stage_counts[stage][pep],
                "enrichment_log2fc": round(log2fc(freq(stage, pep), fb, eps), 4),
                "cyclization": cfg["cyclization"],
                "display_type": cfg["display_type"],
                "source_accession": cfg["source_accession"],
                "is_binder": int(is_binder),
            })

    summary = {
        "target": cfg["target"],
        "source_accession": cfg["source_accession"],
        "display_type": cfg["display_type"],
        "cyclization": cfg["cyclization"],
        "mode": mode,
        "anchors": {"up": up, "down": down} if mode != "rapid_orf_io" else {"up": up, "orf_window_codons": window},
        "codon_range": [min_cod, max_cod] if mode != "rapid_orf_io" else None,
        "stages": stage_order,
        "baseline_stage": baseline,
        "terminal_stage": terminal,
        "enrichment_definition": f"log2((freq_stage+eps)/(freq_{baseline}+eps)); eps=1/min(stage_total)",
        "per_stage_stats": stage_stats,
        "peptides_kept": len(keep),
        "binder_peptides": n_binder,
        "binder_rule": f"terminal({terminal}) count>={binder_min_count} AND log2fc>={binder_log2fc}",
    }
    return rows, summary


def load_padi4(padi4_long_path):
    """Reformat the already-harvested PADI4 long table (reused from S3) into the
    unified schema. Baseline = R2 (as in the original harvest). Binder flag from
    the max round present (R6) using the same tail rule applied downstream, so we
    recompute it here against R6 count + log2FC."""
    rows_by_pep = {}
    with gzip.open(padi4_long_path, "rt") as fh:
        r = csv.DictReader(fh)
        for row in r:
            pep = row["sequence"]
            rows_by_pep.setdefault(pep, []).append(row)
    return rows_by_pep


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fastq-dir", required=True)
    ap.add_argument("--padi4-long", required=True, help="local path to reused PADI4 long csv.gz")
    ap.add_argument("--outdir", required=True)
    ap.add_argument("--name", default="display_ngs_multitarget")
    ap.add_argument("--min-count", type=int, default=3)
    ap.add_argument("--binder-min-count", type=int, default=10)
    ap.add_argument("--binder-log2fc", type=float, default=2.0)
    args = ap.parse_args()
    os.makedirs(args.outdir, exist_ok=True)

    RAPID_CYC = "thioether_ClAc-Cys(head-to-sidechain)"
    PHAGE_CYC = "disulfide/head-to-tail cyclic (Cys-flanked variable)"

    CAMPAIGNS = [
        {   # hPCSK9 -- XL RaPID, single-round input/output (aggregated across P1/P6 x PhoL/Bpa/N3F x reps)
            "target": "hPCSK9 (human PCSK9)",
            "source_accession": "PRJNA1406026",
            "display_type": "mRNA_display_XL_RaPID",
            "cyclization": "photo-crosslinked macrocycle (Bpa/PhoL/N3F reprogrammed internal Met)",
            "mode": "rapid_orf_io",
            "up_anchor": "CATATG",
            "orf_window": 12,
            "stages": [("input", "__HPCSK9_INPUT__"), ("output", "__HPCSK9_OUTPUT__")],
        },
        {   # FIKK13 -- RaPID, 6 rounds (same construct family as PADI4)
            "target": "FIKK13 (P. falciparum FIKK13 kinase)",
            "source_accession": "PRJNA1172558",
            "display_type": "mRNA_display_RaPID",
            "cyclization": RAPID_CYC,
            "mode": "rapid_rounds",
            "up_anchor": "CATATG", "down_anchor": "TGCGGCAGC",
            "min_codons": 6, "max_codons": 12,
            "stages": [("R1", ["SRR30979217.fastq.gz"]), ("R2", ["SRR30979216.fastq.gz"]),
                       ("R3", ["SRR30979215.fastq.gz"]), ("R4", ["SRR30979214.fastq.gz"]),
                       ("R5", ["SRR30979213.fastq.gz"]), ("R6", ["SRR30979212.fastq.gz"])],
        },
        {   # Abeta42 -- M13 phage cyclic (NNK), library -> 7 rounds
            "target": "Abeta42 (amyloid-beta 42)",
            "source_accession": "PRJNA1170358",
            "display_type": "M13_phage_cyclic_peptide",
            "cyclization": PHAGE_CYC,
            "mode": "phage_io",
            "up_anchor": "CACAAC", "down_anchor": "CTCAGT",
            "min_codons": 5, "max_codons": 14,
            "stages": [("library", ["SRR30916250_1.fastq.gz"]),
                       ("selected", ["SRR30916249_1.fastq.gz"])],
        },
        {   # hIAPP -- M13 phage cyclic (NDT), library -> 5 rounds
            "target": "hIAPP (islet amyloid polypeptide / amylin)",
            "source_accession": "PRJNA1170358",
            "display_type": "M13_phage_cyclic_peptide",
            "cyclization": PHAGE_CYC,
            "mode": "phage_io",
            "up_anchor": "CACAAC", "down_anchor": "CTCAGT",
            "min_codons": 5, "max_codons": 14,
            "stages": [("library", ["SRR30916248_1.fastq.gz"]),
                       ("selected", ["SRR30916247_1.fastq.gz"])],
        },
    ]

    # resolve hPCSK9 input/output file lists from the fastq dir
    import glob
    pcsk9_manifest = os.path.join(args.fastq_dir, "..", "pcsk9_runs.tsv")
    in_files, out_files = [], []
    if os.path.exists(pcsk9_manifest):
        with open(pcsk9_manifest) as f:
            for line in f:
                p = line.rstrip("\n").split("\t")
                if len(p) < 2:
                    continue
                acc, lib = p[0], p[1]
                fn = acc + ".fastq.gz"
                if not os.path.exists(os.path.join(args.fastq_dir, fn)):
                    continue
                if "_input_library" in lib and "purified" not in lib:
                    in_files.append(fn)
                elif "_output_library" in lib:
                    out_files.append(fn)
    for c in CAMPAIGNS:
        for i, (lbl, files) in enumerate(c["stages"]):
            if files == "__HPCSK9_INPUT__":
                c["stages"][i] = (lbl, in_files)
            elif files == "__HPCSK9_OUTPUT__":
                c["stages"][i] = (lbl, out_files)

    all_rows = []
    summaries = []

    # ---- PADI4 (reused) ----
    print("[PADI4] reusing S3 harvest", file=sys.stderr)
    padi4 = load_padi4(args.padi4_long)
    padi4_binders = 0
    padi4_rows = 0
    for pep, rws in padi4.items():
        # find R6 (terminal) count + log2fc
        term = None
        for r in rws:
            if r["round"] == "R6":
                term = r
        is_binder = 0
        if term is not None:
            try:
                if int(term["count"]) >= args.binder_min_count and float(term["enrichment_log2fc_vs_baseline"]) >= args.binder_log2fc:
                    is_binder = 1
            except ValueError:
                pass
        if is_binder:
            padi4_binders += 1
        for r in rws:
            all_rows.append({
                "target": "PADI4 (human peptidylarginine deiminase 4)",
                "sequence": pep,
                "n_residues": int(r["n_residues"]),
                "round_or_io": r["round"],
                "count": int(r["count"]),
                "enrichment_log2fc": round(float(r["enrichment_log2fc_vs_baseline"]), 4),
                "cyclization": r["cyclization"],
                "display_type": r["display_type"],
                "source_accession": "PRJNA1188087",
                "is_binder": is_binder,
            })
            padi4_rows += 1
    summaries.append({
        "target": "PADI4 (human peptidylarginine deiminase 4)",
        "source_accession": "PRJNA1188087",
        "display_type": "mRNA_display_RaPID",
        "cyclization": RAPID_CYC,
        "mode": "rapid_rounds (reused from S3 single-target harvest)",
        "stages": ["R2", "R3", "R4", "R5", "R6"], "baseline_stage": "R2", "terminal_stage": "R6",
        "peptides_kept": len(padi4), "binder_peptides": padi4_binders,
        "binder_rule": f"R6 count>={args.binder_min_count} AND log2fc>={args.binder_log2fc}",
        "note": "reused s3://knowledge-datasets-1759951976/.../display_ngs_padi4_rapid/",
    })
    print(f"  [PADI4] peptides={len(padi4):,} rows={padi4_rows:,} binders={padi4_binders:,}", file=sys.stderr)

    # ---- the 4 harvested campaigns ----
    for cfg in CAMPAIGNS:
        print(f"[{cfg['target']}] mode={cfg['mode']}", file=sys.stderr)
        rows, summary = process_campaign(cfg, args.fastq_dir, args.min_count,
                                         args.binder_min_count, args.binder_log2fc)
        all_rows.extend(rows)
        summaries.append(summary)

    # ---- write unified long table ----
    cols = ["target", "sequence", "n_residues", "round_or_io", "count",
            "enrichment_log2fc", "cyclization", "display_type", "source_accession", "is_binder"]
    long_path = os.path.join(args.outdir, f"{args.name}.csv")
    with open(long_path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        for r in all_rows:
            w.writerow(r)

    # ---- per-target peptide/row counts ----
    per_target = {}
    for r in all_rows:
        t = r["target"]
        d = per_target.setdefault(t, {"rows": 0, "peptides": set(), "binders": set()})
        d["rows"] += 1
        d["peptides"].add(r["sequence"])
        if r["is_binder"]:
            d["binders"].add(r["sequence"])
    per_target_out = {t: {"rows": d["rows"], "unique_peptides": len(d["peptides"]),
                          "binder_peptides": len(d["binders"])}
                      for t, d in per_target.items()}

    meta = {
        "name": args.name,
        "n_targets": len(per_target_out),
        "total_rows": len(all_rows),
        "total_unique_peptides_across_targets": sum(v["unique_peptides"] for v in per_target_out.values()),
        "schema": cols,
        "min_count_floor": args.min_count,
        "binder_rule_global": f"terminal/selected count>={args.binder_min_count} AND log2fc>={args.binder_log2fc} (bucket by enriched tail, not quantiles)",
        "per_target": per_target_out,
        "campaigns": summaries,
    }
    meta_path = os.path.join(args.outdir, f"{args.name}_meta.json")
    with open(meta_path, "w") as f:
        json.dump(meta, f, indent=2)

    print("\n=== PER-TARGET SUMMARY ===", file=sys.stderr)
    for t, v in per_target_out.items():
        print(f"  {t}: rows={v['rows']:,} peptides={v['unique_peptides']:,} binders={v['binder_peptides']:,}",
              file=sys.stderr)
    print(f"\nWROTE:\n  {long_path}\n  {meta_path}", file=sys.stderr)


if __name__ == "__main__":
    main()
