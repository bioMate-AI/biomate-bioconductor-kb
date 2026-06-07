#!/usr/bin/env python3
"""IEDB population coverage (Bui et al.) for Plan A epitope–allele pairs."""
from __future__ import annotations

import argparse
import csv
import json
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_PUB = ROOT / "research/anti-virus/runs/publication_20260528T223525Z"

METHOD = (
    "IEDB class I A+B separate; HWE P=1-(1-F)^2 per locus; combine 1-(1-P_A)(1-P_B)"
)


def load_frequencies(freq_tsv: Path) -> dict[str, dict[str, float]]:
    """Return {population: {allele: frequency}} from IEDB/AFND merged TSV."""
    by_pop: dict[str, dict[str, float]] = defaultdict(dict)
    with freq_tsv.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            pop = (row.get("population") or "").strip()
            allele = (row.get("allele") or "").strip()
            if not pop or not allele:
                continue
            if not allele.upper().startswith("HLA-"):
                allele = f"HLA-{allele}"
            by_pop[pop][allele] = float(row["frequency"])
    return dict(by_pop)


def _genotype_freq(allele_freq: float) -> float:
    """Hardy–Weinberg: P(at least one copy) = 1 - (1-F)^2."""
    return 1.0 - (1.0 - allele_freq) ** 2


def _locus_coverage(alleles: list[str], freq_by_allele: dict[str, float]) -> float:
    """IEDB: sum responsive allele frequencies at locus, then single HWE term."""
    f_sum = sum(freq_by_allele.get(a, 0.0) for a in alleles)
    return _genotype_freq(f_sum)


def epitope_coverage(alleles: list[str], freq_by_allele: dict[str, float]) -> float:
    """P(individual presents peptide on ≥1 listed allele), A/B loci independent."""
    a_alleles = sorted({a for a in alleles if "HLA-A" in a.upper()})
    b_alleles = sorted({a for a in alleles if "HLA-B" in a.upper()})
    p_a = _locus_coverage(a_alleles, freq_by_allele) if a_alleles else 0.0
    p_b = _locus_coverage(b_alleles, freq_by_allele) if b_alleles else 0.0
    return 1.0 - (1.0 - p_a) * (1.0 - p_b)

def population_coverage(
    pairs: list[tuple[str, str]],
    freq_by_allele: dict[str, float],
) -> dict[str, float | int | dict]:
    """Union coverage: aggregate responsive alleles by locus, then combine A/B."""
    a_alleles: set[str] = set()
    b_alleles: set[str] = set()
    by_pep: dict[str, set[str]] = defaultdict(set)
    for pep, allele in pairs:
        pep = pep.upper()
        by_pep[pep].add(allele)
        if "HLA-A" in allele.upper():
            a_alleles.add(allele)
        elif "HLA-B" in allele.upper():
            b_alleles.add(allele)

    p_a = _locus_coverage(sorted(a_alleles), freq_by_allele) if a_alleles else 0.0
    p_b = _locus_coverage(sorted(b_alleles), freq_by_allele) if b_alleles else 0.0
    frac = 1.0 - (1.0 - p_a) * (1.0 - p_b)

    per_peptide = {
        pep: epitope_coverage(sorted(alleles), freq_by_allele)
        for pep, alleles in sorted(by_pep.items())
    }

    return {
        "n_epitope_allele_pairs": len(pairs),
        "n_unique_peptides": len(by_pep),
        "coverage_fraction": frac,
        "coverage_percent": round(frac * 100, 2),
        "loci": {
            "HLA-A": {
                "responsive_alleles": sorted(a_alleles),
                "coverage_fraction": p_a,
                "coverage_percent": round(p_a * 100, 2),
            },
            "HLA-B": {
                "responsive_alleles": sorted(b_alleles),
                "coverage_fraction": p_b,
                "coverage_percent": round(p_b * 100, 2),
            },
        },
        "per_peptide_fraction": per_peptide,
        "method": METHOD,
    }


def load_pairs_from_tsv(path: Path) -> list[tuple[str, str]]:
    pairs: list[tuple[str, str]] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) < 2:
            continue
        pep = parts[0].strip().upper()
        for field in parts[1:]:
            for allele in field.split(","):
                a = allele.strip()
                if a:
                    if not a.upper().startswith("HLA-"):
                        a = f"HLA-{a}"
                    pairs.append((pep, a))
    return pairs


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--publication-run", type=Path, default=DEFAULT_PUB)
    ap.add_argument("--input-tsv", type=Path, default=None)
    ap.add_argument("--population", default="Chile")
    ap.add_argument("--freq-tsv", type=Path, default=None)
    args = ap.parse_args()

    pub = args.publication_run.resolve()
    input_tsv = args.input_tsv or (pub / "plan_a_epitope/PLAN_A_CHILE_POP_COVERAGE_INPUT.tsv")
    freq_tsv = args.freq_tsv or (pub / "assets/hla_frequencies_iedb_merged.tsv")

    pairs = load_pairs_from_tsv(input_tsv)
    freqs = load_frequencies(freq_tsv)
    pop_freqs = freqs.get(args.population, {})
    result = population_coverage(pairs, pop_freqs)
    result["analyzed_at"] = datetime.now(timezone.utc).isoformat()
    result["population"] = args.population
    result["input_tsv"] = str(input_tsv)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
