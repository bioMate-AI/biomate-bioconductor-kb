#!/usr/bin/env python3
"""
Science sprint — cross-species GPC conservation for Plan A (ANDV / SNV / PUUV).

Fetches reviewed envelopment polyprotein (GPC) sequences from UniProt REST, aligns with
BioPython when available, otherwise scores k-mer conservation. Maps Plan A peptides from
local epitopeprediction mirrors when present, else derives k-mers from the smoke template FASTA.

Output: research/anti-virus/science_sprint/runs/<timestamp>/track_plan_a_cross_species/cross_species_conservation.json

Usage:
  python3 research/anti-virus/science_sprint/track_plan_a_cross_species.py
"""

from __future__ import annotations

import argparse
import json
import re
import urllib.error
import urllib.parse
import urllib.request
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[3]
TEMPLATE_FASTA = (
    ROOT / "research/anti-virus/runs/plan_a_epitope_samplesheet_template/plan_a_smoke_gp_fragment.fasta"
)
DEFAULT_EPITOPE_MIRROR = ROOT / "research/anti-virus/runs/plan_a_epitope_a44876b7_s3_mirror/predictions/PLAN_A_SMOKE_GP.tsv"

# Reviewed envelopment polyprotein accessions (ANDV / SNV / PUUV reference strains).
DEFAULT_ACCESSIONS = {
    "ANDV": "Q9E006",
    "SNV": "Q89905",
    "PUUV": "P27312",
}
UNIPROT_SEARCH = (
    "reviewed:true AND (protein_name:\"envelopment polyprotein\") "
    "AND (organism_name:Andes OR organism_name:\"Sin Nombre\" OR organism_name:Puumala)"
)


def log(msg: str) -> None:
    print(msg, flush=True)


def fetch_uniprot_fasta(accession: str) -> tuple[str, str]:
    url = f"https://rest.uniprot.org/uniprotkb/{urllib.parse.quote(accession)}.fasta"
    req = urllib.request.Request(url, headers={"User-Agent": "BioMate-plan-a-cross-species/1.0"})
    with urllib.request.urlopen(req, timeout=120) as resp:
        text = resp.read().decode("utf-8", errors="replace")
    lines = text.strip().splitlines()
    if not lines or not lines[0].startswith(">"):
        raise ValueError(f"Invalid FASTA for {accession}")
    header = lines[0][1:].strip()
    seq = "".join(line.strip() for line in lines[1:])
    return header, seq.upper()


def search_hantavirus_gpc() -> list[dict[str, str]]:
    params = urllib.parse.urlencode(
        {
            "query": UNIPROT_SEARCH,
            "fields": "accession,organism_name,protein_name",
            "size": 25,
            "format": "json",
        }
    )
    url = f"https://rest.uniprot.org/uniprotkb/search?{params}"
    req = urllib.request.Request(url, headers={"User-Agent": "BioMate-plan-a-cross-species/1.0"})
    with urllib.request.urlopen(req, timeout=120) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    hits: list[dict[str, str]] = []
    for row in data.get("results") or []:
        org = (row.get("organism") or {}).get("scientificName", "")
        label = "OTHER"
        org_u = org.upper()
        if "ANDES" in org_u:
            label = "ANDV"
        elif "SIN NOMBRE" in org_u:
            label = "SNV"
        elif "PUUMALA" in org_u:
            label = "PUUV"
        hits.append(
            {
                "label": label,
                "accession": row.get("primaryAccession", ""),
                "organism": org,
            }
        )
    return hits


def parse_fasta(path: Path) -> str:
    lines = path.read_text(encoding="utf-8").splitlines()
    return "".join(line.strip() for line in lines if line and not line.startswith(">")).upper()


def load_peptides_from_tsv(tsv_path: Path, *, min_len: int = 8, max_len: int = 12) -> list[str]:
    peptides: set[str] = set()
    header = tsv_path.read_text(encoding="utf-8").splitlines()[0].split("\t")
    try:
        seq_idx = header.index("sequence")
    except ValueError:
        return []
    for line in tsv_path.read_text(encoding="utf-8").splitlines()[1:]:
        if not line.strip():
            continue
        parts = line.split("\t")
        if len(parts) <= seq_idx:
            continue
        pep = parts[seq_idx].strip().upper()
        if min_len <= len(pep) <= max_len and pep.isalpha():
            peptides.add(pep)
    return sorted(peptides)


def derive_peptides_from_fasta(fasta_path: Path, *, k_min: int = 8, k_max: int = 11) -> list[str]:
    seq = parse_fasta(fasta_path)
    peptides: set[str] = set()
    for k in range(k_min, k_max + 1):
        for i in range(len(seq) - k + 1):
            peptides.add(seq[i : i + k])
    return sorted(peptides)


def find_local_epitope_tsv() -> Path | None:
    runs = ROOT / "research/anti-virus/runs"
    candidates = sorted(runs.glob("plan_a_epitope*_s3_mirror/predictions/*.tsv"), reverse=True)
    return candidates[0] if candidates else None


def try_biopython_alignment(sequences: dict[str, str]) -> dict[str, Any] | None:
    try:
        from Bio.Align import PairwiseAligner, substitution_matrices  # type: ignore[import-untyped]
    except ImportError:
        return None

    names = list(sequences.keys())
    if len(names) < 2:
        return None

    matrix = substitution_matrices.load("BLOSUM62")
    aligner = PairwiseAligner()
    aligner.substitution_matrix = matrix
    aligner.open_gap_score = -10
    aligner.extend_gap_score = -0.5

    ref = names[0]
    ref_seq = sequences[ref]
    pairwise: dict[str, Any] = {}
    for other in names[1:]:
        aln = aligner.align(ref_seq, sequences[other])[0]
        aligned_ref = str(aln[0])
        aligned_other = str(aln[1])
        matches = sum(a == b for a, b in zip(aligned_ref, aligned_other, strict=False) if a != "-" and b != "-")
        aligned_cols = sum(1 for a, b in zip(aligned_ref, aligned_other, strict=False) if a != "-" and b != "-")
        identity = matches / aligned_cols if aligned_cols else 0.0
        pairwise[f"{ref}_vs_{other}"] = {
            "identity": round(identity, 4),
            "alignment_length": len(aligned_ref),
            "aligned_ref_preview": aligned_ref[:120],
            "aligned_other_preview": aligned_other[:120],
        }

    return {"method": "biopython_pairwise", "reference": ref, "pairwise": pairwise}


def kmer_conservation(sequences: dict[str, str], k: int = 9) -> dict[str, Any]:
    ref_name, ref_seq = next(iter(sequences.items()))
    other_names = [n for n in sequences if n != ref_name]
    positions: list[dict[str, Any]] = []
    conserved_windows = 0
    for i in range(len(ref_seq) - k + 1):
        kmer = ref_seq[i : i + k]
        if not kmer.isalpha():
            continue
        present = {ref_name: True}
        for name in other_names:
            present[name] = kmer in sequences[name]
        if all(present.values()):
            conserved_windows += 1
        positions.append(
            {
                "start": i + 1,
                "kmer": kmer,
                "conserved_in_all": all(present.values()),
                "present_in": [n for n, ok in present.items() if ok],
            }
        )
    return {
        "method": "kmer_presence",
        "k": k,
        "reference": ref_name,
        "conserved_windows_all_species": conserved_windows,
        "total_windows": len(positions),
        "top_conserved_kmers": [p for p in positions if p["conserved_in_all"]][:50],
    }


def map_peptide_conservation(peptides: list[str], sequences: dict[str, str]) -> list[dict[str, Any]]:
    mapped: list[dict[str, Any]] = []
    for pep in peptides:
        species_hits: dict[str, bool | int | None] = {}
        for name, seq in sequences.items():
            idx = seq.find(pep)
            species_hits[name] = idx + 1 if idx >= 0 else None
        mapped.append(
            {
                "peptide": pep,
                "length": len(pep),
                "found_in": [n for n, pos in species_hits.items() if pos],
                "positions": {n: pos for n, pos in species_hits.items() if pos},
                "cross_species": len([p for p in species_hits.values() if p]) == len(sequences),
            }
        )
    return mapped


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument(
        "--accessions",
        default=",".join(f"{k}:{v}" for k, v in DEFAULT_ACCESSIONS.items()),
        help="Comma-separated LABEL:ACCESSION overrides",
    )
    ap.add_argument("--epitope-tsv", type=Path, default=None, help="Plan A predictions TSV")
    ap.add_argument("--template-fasta", type=Path, default=TEMPLATE_FASTA)
    ap.add_argument("--kmer-size", type=int, default=9)
    ap.add_argument("--out-dir", type=Path, default=None)
    ap.add_argument("--search-uniprot", action="store_true", help="Log UniProt search hits before fetch")
    args = ap.parse_args()

    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    out_dir = args.out_dir or (
        ROOT / "research/anti-virus/science_sprint/runs" / stamp / "track_plan_a_cross_species"
    )
    out_dir.mkdir(parents=True, exist_ok=True)

    accessions: dict[str, str] = {}
    for item in args.accessions.split(","):
        item = item.strip()
        if not item:
            continue
        if ":" not in item:
            raise SystemExit(f"Invalid --accessions entry {item!r}; expected LABEL:ACCESSION")
        label, acc = item.split(":", 1)
        accessions[label.strip()] = acc.strip()

    if args.search_uniprot:
        try:
            hits = search_hantavirus_gpc()
            log(f"UniProt search returned {len(hits)} reviewed envelopment polyprotein hits")
            for hit in hits[:10]:
                log(f"  {hit['label']:5s} {hit['accession']} {hit['organism']}")
        except urllib.error.URLError as exc:
            log(f"UniProt search skipped: {exc!r}")

    sequences: dict[str, str] = {}
    headers: dict[str, str] = {}
    fetch_errors: dict[str, str] = {}
    for label, acc in accessions.items():
        try:
            header, seq = fetch_uniprot_fasta(acc)
            sequences[label] = seq
            headers[label] = header
            log(f"Fetched {label} {acc} ({len(seq)} aa)")
        except Exception as exc:  # noqa: BLE001 - record per-species fetch failure
            fetch_errors[label] = repr(exc)
            log(f"WARNING: failed to fetch {label} ({acc}): {exc!r}")

    if len(sequences) < 2:
        raise SystemExit(f"Need ≥2 sequences for conservation; got {list(sequences)} errors={fetch_errors}")

    epitope_tsv = args.epitope_tsv
    peptide_source = "template_fasta_kmers"
    if epitope_tsv is None:
        epitope_tsv = find_local_epitope_tsv()
    if epitope_tsv and epitope_tsv.is_file():
        peptides = load_peptides_from_tsv(epitope_tsv)
        peptide_source = str(epitope_tsv)
        log(f"Loaded {len(peptides)} peptides from {epitope_tsv}")
    else:
        peptides = derive_peptides_from_fasta(args.template_fasta.resolve())
        log(f"Derived {len(peptides)} k-mers from {args.template_fasta}")

    alignment = try_biopython_alignment(sequences)
    conservation = alignment if alignment else kmer_conservation(sequences, k=args.kmer_size)
    peptide_map = map_peptide_conservation(peptides, sequences)

    cross_species_peptides = [p for p in peptide_map if p["cross_species"]]
    payload = {
        "created_at": datetime.now(timezone.utc).isoformat(),
        "stamp": stamp,
        "uniprot_accessions": accessions,
        "uniprot_headers": headers,
        "fetch_errors": fetch_errors,
        "sequence_lengths": {k: len(v) for k, v in sequences.items()},
        "peptide_source": peptide_source,
        "n_peptides_mapped": len(peptide_map),
        "n_cross_species_peptides": len(cross_species_peptides),
        "conservation": conservation,
        "peptide_conservation": peptide_map,
        "cross_species_peptides": cross_species_peptides[:200],
    }

    out_path = out_dir / "cross_species_conservation.json"
    out_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    log(f"Wrote {out_path}")
    log(
        f"Conservation method={conservation['method']} | "
        f"cross-species peptides={len(cross_species_peptides)}/{len(peptide_map)}"
    )


if __name__ == "__main__":
    main()
