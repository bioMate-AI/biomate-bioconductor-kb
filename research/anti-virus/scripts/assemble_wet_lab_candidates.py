#!/usr/bin/env python3
"""
Assemble publication compute outputs from ANDV campaign in silico results.

Combines:
  - Full-GP cross-species conservation (UniProt ANDV/SNV/PUUV)
  - Plan A epitope science tiers + population coverage (when available)
  - Inhibitor docking / QC summaries (when available)

BioMate scope: **compute only** — no wet-lab synthesis or assays implied.
"""

from __future__ import annotations

import argparse
import csv
import json
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[3]

DEFAULT_ACCESSIONS = {"ANDV": "Q9E006", "SNV": "Q89905", "PUUV": "P27312"}


def fetch_uniprot_fasta(accession: str) -> str:
    url = f"https://rest.uniprot.org/uniprotkb/{urllib.parse.quote(accession)}.fasta"
    req = urllib.request.Request(url, headers={"User-Agent": "BioMate-wet-lab/1.0"})
    with urllib.request.urlopen(req, timeout=120) as resp:
        text = resp.read().decode("utf-8", errors="replace")
    return "".join(line.strip() for line in text.splitlines()[1:]).upper()


def kmer_conservation_all_species(sequences: dict[str, str], k: int = 9) -> list[dict[str, Any]]:
    ref_name, ref_seq = next(iter(sequences.items()))
    other_names = [n for n in sequences if n != ref_name]
    conserved: list[dict[str, Any]] = []
    for i in range(len(ref_seq) - k + 1):
        kmer = ref_seq[i : i + k]
        if not kmer.isalpha():
            continue
        if all(kmer in sequences[n] for n in other_names):
            conserved.append(
                {
                    "peptide": kmer,
                    "gp_position_start": i + 1,
                    "length": k,
                    "species": list(sequences.keys()),
                    "rationale": "100% k-mer presence across ANDV/SNV/PUUV full GPC",
                }
            )
    return conserved


def load_epitope_binders(tsv_path: Path, *, affinity_threshold: float = 0.5) -> list[dict[str, Any]]:
    if not tsv_path.is_file():
        return []
    lines = tsv_path.read_text(encoding="utf-8").splitlines()
    if not lines:
        return []
    header = lines[0].split("\t")
    binders: list[dict[str, Any]] = []
    col = {name: idx for idx, name in enumerate(header)}
    for line in lines[1:]:
        parts = line.split("\t")
        if len(parts) < len(header):
            continue
        is_binder = parts[col.get("binder", -1)].lower() == "true" if "binder" in col else False
        affinity = float(parts[col["affinity"]]) if "affinity" in col else 0.0
        if is_binder or affinity >= affinity_threshold:
            binders.append(
                {
                    "peptide": parts[col.get("sequence", 0)],
                    "allele": parts[col["allele"]] if "allele" in col else "",
                    "rank": float(parts[col["rank"]]) if "rank" in col else None,
                    "BA": float(parts[col["BA"]]) if "BA" in col else affinity,
                    "affinity": affinity,
                    "binder": is_binder,
                    "tool": parts[col.get("predictor", col.get("tool", ""))] if "predictor" in col or "tool" in col else "mhcnuggets",
                }
            )
    binders.sort(key=lambda b: (b.get("rank") is None, b.get("rank") or 999))
    return binders


def load_docking_hits(docking_json: Path, *, top_n: int = 20) -> list[dict[str, Any]]:
    if not docking_json.is_file():
        return []
    data = json.loads(docking_json.read_text(encoding="utf-8"))
    hits: list[dict[str, Any]] = []
    for entry in data.get("results") or data.get("docking_results") or []:
        score = (
            entry.get("best_affinity_kcal_mol")
            or entry.get("best_score")
            or entry.get("score")
            or entry.get("affinity")
        )
        if score is None:
            continue
        hits.append(
            {
                "compound": entry.get("compound_id") or entry.get("smiles", "")[:40],
                "smiles": entry.get("smiles", ""),
                "score_kcal_mol": score,
                "receptor": entry.get("receptor") or entry.get("pdb_id", "9P3I"),
            }
        )
    hits.sort(key=lambda x: float(x["score_kcal_mol"]))
    return hits[:top_n]


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--publication-run", type=Path, required=True)
    ap.add_argument("--epitope-tsv", type=Path, default=None)
    ap.add_argument("--conservation-json", type=Path, default=None)
    ap.add_argument("--docking-json", type=Path, default=None)
    ap.add_argument("--kmer-size", type=int, default=9)
    args = ap.parse_args()

    pub_dir = args.publication_run.resolve()
    out_dir = pub_dir / "compute_package"
    out_dir.mkdir(parents=True, exist_ok=True)

    if args.conservation_json and args.conservation_json.is_file():
        cdata = json.loads(args.conservation_json.read_text(encoding="utf-8"))
        conserved_list = [
            {
                "peptide": p["peptide"],
                "gp_position_start": p["positions"]["ANDV"],
                "length": p["length"],
                "species": p.get("found_in", []),
                "rationale": "cross_species from track_plan_a_cross_species.py",
            }
            for p in cdata.get("cross_species_peptides", [])
            if p.get("length") == args.kmer_size and p.get("cross_species")
        ]
        conserved_list = sorted({c["peptide"]: c for c in conserved_list}.values(), key=lambda x: x["gp_position_start"])
    else:
        sequences: dict[str, str] = {}
        for label, acc in DEFAULT_ACCESSIONS.items():
            sequences[label] = fetch_uniprot_fasta(acc)
        conserved = kmer_conservation_all_species(sequences, k=args.kmer_size)
        conserved_list = sorted({c["peptide"]: c for c in conserved}.values(), key=lambda x: x["gp_position_start"])

    epitope_tsv = args.epitope_tsv
    if epitope_tsv is None:
        preferred = pub_dir / "plan_a_epitope/PLAN_A_CONSENSUS_BINDERS.tsv"
        if preferred.is_file():
            epitope_tsv = preferred
        else:
            candidates = sorted(pub_dir.glob("plan_a_epitope/PLAN_A_FULL_GP_*.tsv"))
            epitope_tsv = candidates[0] if candidates else None
    binders = load_epitope_binders(epitope_tsv) if epitope_tsv else []
    if not binders and epitope_tsv and "CONSENSUS" in epitope_tsv.name.upper():
        with epitope_tsv.open(newline="", encoding="utf-8") as f:
            binders = [
                {"peptide": (r.get("sequence") or "").upper(), "allele": r.get("allele", ""), "binder": True}
                for r in csv.DictReader(f, delimiter="\t")
            ]

    tiers_json = pub_dir / "plan_a_epitope/PLAN_A_SCIENCE_TIERS.json"
    science_tiers: list[dict[str, Any]] = []
    if tiers_json.is_file():
        tiers_data = json.loads(tiers_json.read_text(encoding="utf-8"))
        science_tiers = tiers_data.get("peptide_ranked") or []

    processing_json = pub_dir / "plan_a_epitope/PLAN_A_PROCESSING_PROXY.json"
    processing_by_pep: dict[str, bool] = {}
    if processing_json.is_file():
        pdata = json.loads(processing_json.read_text(encoding="utf-8"))
        for r in pdata.get("results") or []:
            processing_by_pep[r["peptide"]] = bool(r.get("processing_likely"))

    docking_json = args.docking_json
    if docking_json is None:
        zinc150_vina = pub_dir / "zinc150_screen" / "vina" / "docking_autodock_vina_results.json"
        if zinc150_vina.is_file():
            docking_json = zinc150_vina
        else:
            candidates = sorted(
                (ROOT / "research/anti-virus/science_sprint/runs").glob(
                    "*/track_inh_ensemble/ensemble_results.json"
                ),
                reverse=True,
            )
            docking_json = candidates[0] if candidates else None
    docking_hits = load_docking_hits(docking_json) if docking_json else []
    docked_total = 0
    if docking_json and docking_json.is_file():
        docked_total = len(json.loads(docking_json.read_text(encoding="utf-8")).get("results") or [])

    chile_cov_pct: float | None = None
    chile_cov_path = pub_dir / "plan_a_epitope/PLAN_A_CHILE_POPULATION_COVERAGE.json"
    if chile_cov_path.is_file():
        cdata = json.loads(chile_cov_path.read_text(encoding="utf-8"))
        tier = (cdata.get("subsets") or {}).get("tier_A_B_surface") or {}
        chile = (tier.get("by_population") or {}).get("Chile") or {}
        if chile.get("coverage_percent") is not None:
            chile_cov_pct = float(chile["coverage_percent"])

    binder_seqs = {b["peptide"].upper() for b in binders}
    vaccine_candidates: list[dict[str, Any]] = []
    for rank, c in enumerate(conserved_list[:100], start=1):
        pep = c["peptide"]
        vaccine_candidates.append(
            {
                "id": f"XSP-{rank:02d}",
                "peptide": pep,
                "position": c["gp_position_start"],
                "length": c["length"],
                "cross_species_conserved": True,
                "mhc_binder_validated": pep in binder_seqs,
                "order_priority": "HIGH" if pep in binder_seqs else "MEDIUM",
                "compute_role": "cross_species_conserved_kmer",
            }
        )

    seen_pep: set[str] = set()
    mhc_binder_candidates: list[dict[str, Any]] = []
    if science_tiers:
        for rank, p in enumerate(science_tiers, start=1):
            pep = p["peptide"].upper()
            if pep in seen_pep or p.get("best_tier") not in ("A", "B", "C"):
                continue
            if p.get("best_tier") == "C":
                continue
            seen_pep.add(pep)
            alleles = p.get("alleles") or []
            mhc_binder_candidates.append(
                {
                    "id": f"HC-{len(mhc_binder_candidates)+1:02d}",
                    "peptide": pep,
                    "science_tier": p.get("best_tier"),
                    "best_allele": alleles[0] if alleles else "",
                    "alleles": alleles,
                    "gp_position": p.get("gp_position"),
                    "gpc_region": p.get("gpc_region"),
                    "cross_species_conserved": p.get("cross_species_conserved"),
                    "processing_likely": processing_by_pep.get(pep),
                    "order_priority": "HIGH" if p.get("best_tier") == "A" else "MEDIUM",
                    "compute_role": "tier_ranked_epitope_candidate",
                }
            )
            if len(mhc_binder_candidates) >= 20:
                break
    else:
        for b in binders:
            pep = b["peptide"].upper()
            if pep in seen_pep:
                continue
            seen_pep.add(pep)
            mhc_binder_candidates.append(
                {
                    "id": f"MB-{len(mhc_binder_candidates)+1:02d}",
                    "peptide": pep,
                    "best_allele": b["allele"],
                    "rank": b.get("rank"),
                    "BA": b.get("BA"),
                    "cross_species_conserved": pep in {c["peptide"] for c in conserved_list},
                    "order_priority": "HIGH",
                    "compute_role": "mhc_binder_candidate",
                }
            )
            if len(mhc_binder_candidates) >= 20:
                break

    inhibitor_candidates: list[dict[str, Any]] = []
    for rank, h in enumerate(docking_hits[:20], start=1):
        inhibitor_candidates.append(
            {
                "id": f"INH-{rank:02d}",
                "smiles": h.get("smiles") or h.get("compound", ""),
                "score_kcal_mol": h["score_kcal_mol"],
                "receptor": h.get("receptor", "9P3I"),
                "order_priority": "HIGH" if rank <= 5 else "MEDIUM",
                "compute_role": "docking_hit_in_silico",
            }
        )

    package = {
        "assembled_at": datetime.now(timezone.utc).isoformat(),
        "data_sources": {
            "uniprot_accessions": DEFAULT_ACCESSIONS,
            "epitope_tsv": str(epitope_tsv) if epitope_tsv else None,
            "docking_json": str(docking_json) if docking_json else None,
        },
        "summary": {
            "conserved_9mers_full_gp": len(conserved_list),
            "mhc_binders": len(binders),
            "mhc_binder_unique_peptides": len(seen_pep),
            "science_tier_ranked": len(science_tiers),
            "conserved_binder_overlap": sum(1 for v in vaccine_candidates if v["mhc_binder_validated"]),
            "docking_hits": len(docking_hits),
            "zinc_screen_docked": docked_total,
            "chile_tier_ab_coverage_pct": chile_cov_pct,
            "top_vaccine_candidates": len(vaccine_candidates),
            "inhibitor_compute_lead": "INH-01",
            "inhibitor_compute_lead_note": "Vina + pose QC; Z600-R1 better Vina (−6.527) but not promoted",
        },
        "science_tier_track": mhc_binder_candidates,
        "conservation_track": vaccine_candidates[:30],
        "mhc_binder_track": mhc_binder_candidates,
        "inhibitor_docking_track": inhibitor_candidates,
        "vaccine_peptide_candidates": vaccine_candidates[:30],
        "mhc_binders": binders[:100],
        "inhibitor_docking_hits": docking_hits,
    }

    json_path = out_dir / "compute_candidates.json"
    json_path.write_text(json.dumps(package, indent=2), encoding="utf-8")

    md_lines = [
        "# ANDV Compute Output Package (BioMate in silico)",
        "",
        f"Generated: {package['assembled_at']}",
        "",
        "_No wet-lab work — ranked compute artifacts for manuscript / workflow demo._",
        "",
        "## Summary",
        f"- Cross-species conserved {args.kmer_size}-mers (full GP): **{len(conserved_list)}**",
        f"- MHC binders (epitope run): **{len(binders)}** ({len(seen_pep)} unique peptides)",
        f"- Conserved ∩ binder overlap: **{sum(1 for v in vaccine_candidates if v['mhc_binder_validated'])}**",
        f"- Docking hits (top ranked): **{len(docking_hits)}**",
        f"- ZINC screen docked: **{docked_total}**",
        f"- Inhibitor compute lead: **INH-01** (Vina + pose QC; Z600-R1 backup)",
    ]
    if chile_cov_pct is not None:
        md_lines.append(
            f"- Chile tier A+B population coverage (17-allele strict dual): **{chile_cov_pct:.2f}%**"
        )
    md_lines.extend(
        [
            "",
            "## Track A — Tier-ranked epitope candidates (MHCnuggets + MHCflurry consensus)",
            "",
            "_Ranked by dual MHCnuggets+MHCflurry consensus + GPC surface exposure. Tier C (cytoplasmic) excluded._",
            "",
            "| ID | Peptide | Tier | GP pos | Region | Conserved | Processing proxy | Priority |",
            "|----|---------|------|--------|--------|-----------|------------------|----------|",
        ]
    )
    for m in mhc_binder_candidates[:15]:
        proc = m.get("processing_likely")
        proc_s = "yes" if proc is True else ("no" if proc is False else "—")
        md_lines.append(
            f"| {m['id']} | {m['peptide']} | {m.get('science_tier', '—')} | "
            f"{m.get('gp_position', '—')} | {m.get('gpc_region', '—')} | "
            f"{'yes' if m.get('cross_species_conserved') else 'no'} | {proc_s} | {m['order_priority']} |"
        )
    md_lines.extend(
        [
            "",
            "## Track B — Cross-species conserved 9-mers (breadth)",
            "",
            "| ID | Peptide | GP pos | MHC binder | Priority |",
            "|----|---------|--------|------------|----------|",
        ]
    )
    for v in vaccine_candidates[:15]:
        md_lines.append(
            f"| {v['id']} | {v['peptide']} | {v['position']} | "
            f"{'yes' if v['mhc_binder_validated'] else 'pending'} | {v['order_priority']} |"
        )
    if docking_hits:
        md_lines.extend(
            [
                "",
                "## Track C — ZINC library docking hits (9P3I top pocket)",
                "",
                "| ID | SMILES (truncated) | Vina (kcal/mol) | Receptor | Priority |",
                "|----|-------------------|-----------------|----------|----------|",
            ]
        )
        for h in inhibitor_candidates[:15]:
            sm = (h.get("smiles") or "")[:48]
            md_lines.append(
                f"| {h['id']} | `{sm}` | **{h['score_kcal_mol']}** | {h['receptor']} | {h['order_priority']} |"
            )

    md_path = out_dir / "COMPUTE_CANDIDATES.md"
    md_path.write_text("\n".join(md_lines) + "\n", encoding="utf-8")
    print(f"Wrote {json_path}")
    print(f"Wrote {md_path}")
    print(f"Conserved 9-mers: {len(conserved_list)} | MHC binders: {len(binders)} | Docking hits: {len(docking_hits)}")


if __name__ == "__main__":
    main()
