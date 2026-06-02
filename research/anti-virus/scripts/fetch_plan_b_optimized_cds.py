#!/usr/bin/env python3
"""Generate human-codon-optimized ANDV GP CDS FASTA for Plan B wet-lab bundle."""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "backend/biomni_workflows/galaxy/tools/biomni/_lib"))

from synthetic_biology import optimize_codons_for_heterologous_expression  # noqa: E402

# Human codon usage (fraction) — subset from Kazusa / common mRNA vaccine hosts
HUMAN_CODON_USAGE = {
    "TTT": 0.45, "TTC": 0.55, "TTA": 0.07, "TTG": 0.13, "CTT": 0.13, "CTC": 0.20,
    "CTA": 0.07, "CTG": 0.52, "ATT": 0.36, "ATC": 0.48, "ATA": 0.16, "ATG": 1.00,
    "GTT": 0.18, "GTC": 0.24, "GTA": 0.11, "GTG": 0.47, "TCT": 0.18, "TCC": 0.22,
    "TCA": 0.15, "TCG": 0.06, "TAT": 0.43, "TAC": 0.57, "TAA": 0.30, "TAG": 0.24,
    "TGA": 0.47, "TGT": 0.45, "TGC": 0.55, "TGG": 1.00, "CCT": 0.28, "CCC": 0.33,
    "CCA": 0.27, "CCG": 0.11, "CAT": 0.41, "CAC": 0.59, "CAA": 0.25, "CAG": 0.75,
    "CGT": 0.08, "CGC": 0.19, "CGA": 0.11, "CGG": 0.21, "AGT": 0.15, "AGC": 0.24,
    "AGA": 0.20, "AGG": 0.20, "GCT": 0.26, "GCC": 0.40, "GCA": 0.23, "GCG": 0.11,
    "GAT": 0.46, "GAC": 0.54, "GAA": 0.42, "GAG": 0.58, "GGT": 0.16, "GGC": 0.34,
    "GGA": 0.25, "GGG": 0.25,
}

DEFAULT_IN = ROOT / "research/anti-virus/runs/publication_20260528T223525Z/assets/andv_gp_cds_reverse_translated.fasta"
DEFAULT_OUT = ROOT / "research/anti-virus/runs/publication_20260528T223525Z/plan_b_codon/andv_gp_optimized_cds.fasta"


def read_fasta_seq(path: Path) -> str:
    lines = path.read_text().splitlines()
    return "".join(l for l in lines if not l.startswith(">"))


def wrap_fasta(header: str, seq: str, width: int = 80) -> str:
    body = "\n".join(seq[i : i + width] for i in range(0, len(seq), width))
    return f">{header}\n{body}\n"


def main() -> None:
    import argparse

    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--input", type=Path, default=DEFAULT_IN)
    ap.add_argument("--output", type=Path, default=DEFAULT_OUT)
    ap.add_argument("--summary-json", type=Path, default=DEFAULT_OUT.with_suffix(".summary.json"))
    args = ap.parse_args()

    seq = read_fasta_seq(args.input)
    cwd = Path.cwd()
    log = optimize_codons_for_heterologous_expression(seq, HUMAN_CODON_USAGE)
    opt_path = cwd / "optimized_sequence.txt"
    if not opt_path.is_file():
        raise SystemExit("optimize_codons did not write optimized_sequence.txt")

    optimized = opt_path.read_text().strip()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        wrap_fasta("ANDV_GP_Q9E006_human_codon_optimized publication_20260528T223525Z", optimized)
    )
    summary = {
        "input_fasta": str(args.input),
        "output_fasta": str(args.output),
        "length_nt": len(optimized),
        "n_codons": len(optimized) // 3,
        "host": "human",
        "log_excerpt": log.splitlines()[:20],
    }
    args.summary_json.write_text(json.dumps(summary, indent=2))
    print(f"Wrote {args.output} ({len(optimized)} nt)")
    print(f"Summary: {args.summary_json}")


if __name__ == "__main__":
    main()
