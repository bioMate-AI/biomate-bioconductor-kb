#!/usr/bin/env python3
"""Harvest + process RaPID / mRNA-display selection NGS into an enrichment-labeled
cyclic-peptide table (sequence, round, count, frequency, enrichment).

Primary signal for the inverted-data-dependency cyclic LLM
(docs/20261005_INNOVATION_THESIS_CYCLIC_LLM.md,
 docs/20261004_CYCLIC_PEPTIDE_DATA_WALL_STRATEGY.md,
 docs/20261005_DISPLAY_NGS_HARVEST.md).

Raw display NGS are DNA reads, NOT peptides. This script performs the three
processing steps every display-NGS harvest needs:
  1. TRANSLATE   — locate the variable coding region between the fixed upstream
                   start (ATG, inside the ...CATATG NdeI motif) and the fixed
                   downstream Cys+GS linker (TGCGGCAGC), translate the (NNK)n
                   codons to amino acids.
  2. CYCLIZATION — RaPID macrocycles close as a thioether between the
                   N-terminal chloroacetyl (ClAc) initiator (reprogrammed AUG)
                   and the thiol of the fixed downstream Cys (TGC). So the
                   cyclic macrocycle = [ClAc-init] + (NNK)n + Cys. We record the
                   variable residues (the diversity) and annotate cyclization.
  3. ENRICHMENT  — per-round frequency; the binding-signal label is the
                   round-over-round log2 fold-change of a peptide's frequency
                   (late round vs. baseline round). Enrichment across panning
                   rounds IS the (quantitative) binding signal.

Dataset harvested here (default manifest): PRJNA1188087 / SRP546185
"Discovering Covalent Cyclic Peptide Inhibitors of PADI4 Using mRNA Display with
a Genetically Encoded Electrophilic Warhead" (Imperial College London).
Read structure from the SRA DESIGN_DESCRIPTION (SRR31398309 et al.):
  5'-TAATACGACTCACTATAGGG TTAACTTTAAGAAGGAGATATA CATATG (NNK)n
     TGCGGCAGCGGCAGCGGCAGC TAG GACGGGGGGCGGAAA-3'
  n in {6..12} NNK codons; single 151-cycle MiSeq v3 reads.

Reusable for other mRNA-display / RaPID studies by passing --manifest,
--up-anchor, --down-anchor, --min-codons, --max-codons.

Usage:
  python3 harvest_display_ngs_rapid.py \
      --manifest manifest.tsv --outdir OUT --name padi4_rapid_15min

manifest.tsv (tab-separated, no header): <round_label>\t<path_to_fastq.gz>
"""
import argparse, csv, gzip, json, math, os, sys
from collections import Counter, defaultdict

# ---- standard DNA codon table ----
BASES = "TCAG"
AAS = "FFLLSSSSYY**CC*WLLLLPPPPHHQQRRRRIIIMTTTTNNKKSSRRVVVVAAAADDEEGGGG"
CODON = {a + b + c: AAS[i]
         for i, (a, b, c) in enumerate((x, y, z) for x in BASES for y in BASES for z in BASES)}
COMP = str.maketrans("ACGTN", "TGCAN")


def revcomp(s):
    return s.translate(COMP)[::-1]


def translate(nt):
    aa = []
    for i in range(0, len(nt) - 2, 3):
        c = CODON.get(nt[i:i + 3], "X")
        aa.append(c)
    return "".join(aa)


def extract_peptide(read, up, down, min_cod, max_cod):
    """Return variable (dna, aa) for whichever strand carries both anchors, else None."""
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
        if "*" in aa:          # amber/stop in variable region -> non-productive
            continue
        if "X" in aa:
            continue
        return var, aa
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", required=True, help="TSV: round_label<TAB>fastq.gz")
    ap.add_argument("--outdir", required=True)
    ap.add_argument("--name", required=True)
    ap.add_argument("--up-anchor", default="CATATG",
                    help="constant seq ending in the ATG start; variable region begins after it")
    ap.add_argument("--down-anchor", default="TGCGGCAGC",
                    help="constant Cys(TGC)+GS linker; variable region ends before it")
    ap.add_argument("--min-codons", type=int, default=6)
    ap.add_argument("--max-codons", type=int, default=12)
    ap.add_argument("--min-count", type=int, default=3,
                    help="drop peptides whose max per-round count < this (sequencing-error floor)")
    ap.add_argument("--baseline-round", default=None,
                    help="round label used as enrichment denominator (default: first in manifest)")
    args = ap.parse_args()

    os.makedirs(args.outdir, exist_ok=True)
    rounds = []
    with open(args.manifest) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            lbl, path = line.split("\t")[:2]
            rounds.append((lbl, path))
    baseline = args.baseline_round or rounds[0][0]

    # per-round peptide counts + QC stats
    counts = {lbl: Counter() for lbl, _ in rounds}
    stats = {}
    for lbl, path in rounds:
        total = productive = 0
        c = counts[lbl]
        with gzip.open(path, "rt") as fh:
            for n, line in enumerate(fh):
                if n % 4 != 1:      # fastq: sequence line is line 2 of every 4
                    continue
                total += 1
                r = extract_peptide(line.strip(), args.up_anchor, args.down_anchor,
                                    args.min_codons, args.max_codons)
                if r is None:
                    continue
                productive += 1
                c[r[1]] += 1        # key on AA sequence of the variable region
        stats[lbl] = {"reads": total, "productive": productive,
                      "productive_pct": round(100 * productive / max(total, 1), 2),
                      "unique_peptides": len(c)}
        print(f"[{lbl}] reads={total:,} productive={productive:,} "
              f"({stats[lbl]['productive_pct']}%) unique={len(c):,}", file=sys.stderr)

    round_totals = {lbl: sum(c.values()) for lbl, c in counts.items()}

    # universe of peptides passing the min-count floor in any round
    keep = set()
    for lbl, c in counts.items():
        for pep, n in c.items():
            if n >= args.min_count:
                keep.add(pep)

    def freq(lbl, pep):
        t = round_totals[lbl]
        return counts[lbl][pep] / t if t else 0.0

    eps = 1.0 / max(1, min(t for t in round_totals.values() if t))  # pseudocount for log2FC

    # ---- long table: sequence, round, count, frequency, enrichment ----
    long_path = os.path.join(args.outdir, f"display_ngs_{args.name}.csv")
    round_order = [lbl for lbl, _ in rounds]
    with open(long_path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["sequence", "n_residues", "round", "count", "frequency",
                    "enrichment_log2fc_vs_baseline", "cyclization", "display_type"])
        for pep in sorted(keep):
            fb = freq(baseline, pep)
            for lbl in round_order:
                cnt = counts[lbl][pep]
                fr = freq(lbl, pep)
                enr = math.log2((fr + eps) / (fb + eps))
                w.writerow([pep, len(pep), lbl, cnt, f"{fr:.3e}", f"{enr:.4f}",
                            "thioether_ClAc-Cys(head-to-sidechain)", "mRNA_display_RaPID"])

    # ---- wide enrichment summary (one row per peptide) ----
    wide_path = os.path.join(args.outdir, f"display_ngs_{args.name}_enrichment.csv")
    with open(wide_path, "w", newline="") as f:
        w = csv.writer(f)
        hdr = ["sequence", "n_residues"] + [f"count_{l}" for l in round_order] + \
              [f"freq_{l}" for l in round_order] + \
              [f"log2fc_{l}_vs_{baseline}" for l in round_order] + ["max_count"]
        w.writerow(hdr)
        rows = []
        for pep in keep:
            fb = freq(baseline, pep)
            crow = [counts[l][pep] for l in round_order]
            frow = [freq(l, pep) for l in round_order]
            lrow = [math.log2((fr + eps) / (fb + eps)) for fr in frow]
            rows.append((max(crow), pep, crow, frow, lrow))
        rows.sort(reverse=True)  # most abundant first
        for mx, pep, crow, frow, lrow in rows:
            w.writerow([pep, len(pep)] + crow +
                       [f"{x:.3e}" for x in frow] + [f"{x:.4f}" for x in lrow] + [mx])

    meta = {
        "name": args.name,
        "bioproject": "PRJNA1188087",
        "sra_study": "SRP546185",
        "display_type": "mRNA_display_RaPID_covalent",
        "target": "human PADI4 (peptidylarginine deiminase 4)",
        "cyclization": "thioether macrocycle: N-terminal ClAc initiator (reprogrammed AUG) + downstream Cys (TGC)",
        "noncanonical_chemistry": "ClAc initiator (ncAA warhead); RaPID supports N-methyl/ncAA via genetic code reprogramming",
        "rounds": round_order,
        "baseline_round": baseline,
        "up_anchor": args.up_anchor,
        "down_anchor": args.down_anchor,
        "codon_range": [args.min_codons, args.max_codons],
        "min_count_floor": args.min_count,
        "per_round_stats": stats,
        "round_totals_productive": round_totals,
        "peptides_kept": len(keep),
        "enrichment_definition": "log2((freq_round+eps)/(freq_baseline+eps)); eps=1/min(round_total)",
        "schema_long": ["sequence", "n_residues", "round", "count", "frequency",
                        "enrichment_log2fc_vs_baseline", "cyclization", "display_type"],
        "source": "ENA fastq (ftp.sra.ebi.ac.uk); Imperial College London; covalent RaPID PADI4",
    }
    meta_path = os.path.join(args.outdir, f"display_ngs_{args.name}_meta.json")
    with open(meta_path, "w") as f:
        json.dump(meta, f, indent=2)

    print(f"\nWROTE:\n  {long_path}\n  {wide_path}\n  {meta_path}", file=sys.stderr)
    print(f"peptides_kept={len(keep):,}", file=sys.stderr)


if __name__ == "__main__":
    main()
