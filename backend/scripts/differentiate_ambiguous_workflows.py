"""Targeted catalog quality fix — make ambiguous workflow descriptions and
annotation_v2 fields more differentiating.

Scope: 4 workflows where the description/annotation does not distinguish
the *execution shape* even when the *statistical intent* overlaps.

  deseq2                                          — bare Bioc R/Markdown workflow
  nf-core/differentialabundance                   — nf-core multi-method pipeline
  clusterprofiler                                 — ORA on a gene list
  clusterprofiler_gene_set_enrichment_analysis    — GSEA on a ranked list

The clusterProfiler pair had IDENTICAL annotation_v2.when_to_use and
.alternatives (copy-paste bug). The deseq2 / differentialabundance pair
had an asymmetric data state: deseq2.annotation_v2 was rich,
differentialabundance.annotation_v2 was empty, biasing retrieval.

Usage:
    python scripts/differentiate_ambiguous_workflows.py --dry-run    # print
    python scripts/differentiate_ambiguous_workflows.py --apply      # write
"""
from __future__ import annotations

import argparse
import json
import sqlite3
import sys
import time
from pathlib import Path

DB = Path(__file__).resolve().parents[1] / "database" / "galaxy_ai_tools.db"

UPDATES: dict[str, dict[str, str]] = {
    "deseq2": {
        "description": (
            "Bare Bioconductor R/Markdown workflow for differential expression on a "
            "raw count matrix using a single method (DESeq2's negative-binomial GLM "
            "with empirical Bayes shrinkage). Designed for programmatic R control, "
            "reproducible R Markdown reports with full sessionInfo, and Bioconductor-"
            "style consensus DE comparisons (pair with edgeR / limma / DSS / EBSeq / "
            "IHW in separate steps). For a one-click multi-method nf-core pipeline "
            "that bundles DESeq2 + edgeR + limma + GSEA + HTML report, use "
            "nf-core/differentialabundance instead."
        ),
    },
    "nf-core/differentialabundance": {
        # description is already detailed; only annotation_v2 needs to be filled in.
        "annotation_v2": (
            "- key_parameters: study.name=Study identifier ;; "
            "study.contrasts=List of contrasts between condition groups ;; "
            "methods=Subset of {deseq2, limma, voom} to run in parallel ;; "
            "gsea.run=Whether to run GSEA on ranked stats ;; "
            "gsea.gene_sets=MSigDB collection (H, C2, C5 etc.) ;; "
            "reporting.report_path=Where to write the bundled HTML report\n"
            "- alternatives: deseq2=Use bare-Bioconductor deseq2 workflow when you want "
            "full R control, R Markdown narrative output, and a single statistical "
            "method (no multi-method consensus) ;; "
            "salmon-only DE pipelines=Use when you already have transcript-level "
            "Salmon quants ;; "
            "nf-core/rnaseq=Use for raw FASTQ processing UPSTREAM of this pipeline\n"
            "- when_to_use: When you already have a gene/transcript count matrix and "
            "want a one-click nf-core pipeline that runs DESeq2 + limma-voom (and "
            "optionally edgeR) in parallel, bundles GSEA over MSigDB/KEGG/Reactome, "
            "and emits a single HTML report with volcano plots, heatmaps, and PCA. "
            "Production-grade FAIR outputs.\n"
            "- pitfalls: Providing raw FASTQ instead of a count matrix (run "
            "nf-core/rnaseq first) ;; "
            "Forgetting to specify a contrasts file (the pipeline cannot infer "
            "comparisons) ;; "
            "Treating the bundled HTML report as the final word — for novel biology, "
            "follow up with the bare-Bioc deseq2 workflow for full diagnostic plots "
            "and Bayesian shrinkage tuning"
        ),
    },
    "clusterprofiler": {
        "description": (
            "Over-Representation Analysis (ORA) on an unranked gene list — "
            "Fisher / hypergeometric test for GO terms and pathways. Input is a "
            "DISCRETE gene list (typically DE up- or down-regulated genes at FDR "
            "< threshold) tested against a background universe. For ranked-list "
            "(GSEA) enrichment use clusterprofiler_gene_set_enrichment_analysis."
        ),
        "annotation_v2": (
            "- key_parameters: gene=Vector of gene IDs (the foreground set) ;; "
            "universe=Background gene list (defaults to all annotated genes in the "
            "OrgDb) ;; "
            "OrgDb=Bioconductor organism annotation (e.g., org.Hs.eg.db) ;; "
            "ont=GO ontology branch (BP / MF / CC) ;; "
            "pvalueCutoff=Hypergeometric p-value cutoff ;; "
            "qvalueCutoff=BH-adjusted q-value cutoff\n"
            "- alternatives: clusterprofiler_gene_set_enrichment_analysis=Use this "
            "for ranked-list (GSEA) enrichment instead of discrete-list ORA ;; "
            "topGO=Alternative ORA package with weighting that accounts for GO term "
            "hierarchy ;; "
            "goseq=Use when probability of selection is biased by gene length "
            "(common in RNA-seq DE)\n"
            "- when_to_use: When you have a DISCRETE gene list (e.g., DE up- or "
            "down-regulated genes at FDR < threshold) and want to test which "
            "biological themes are over-represented relative to a background. NOT "
            "for ranked statistic input.\n"
            "- pitfalls: Using a ranked list and discarding the rank information "
            "(use GSEA variant instead) ;; "
            "Not specifying a relevant universe (the test silently uses all "
            "annotated genes, which may be biased) ;; "
            "Mixing Entrez and Ensembl ID types between gene list and OrgDb"
        ),
    },
    "clusterprofiler_gene_set_enrichment_analysis": {
        "description": (
            "Gene Set Enrichment Analysis (GSEA) on a RANKED list of genes — "
            "Kolmogorov–Smirnov-style running-sum test over a ranked statistic "
            "(e.g., DE log2 fold-change or signed -log10 p). Detects coordinated "
            "pathway shifts even when no single gene crosses the FDR threshold. "
            "For discrete-list (ORA) enrichment use clusterprofiler instead."
        ),
        "annotation_v2": (
            "- key_parameters: geneList=NAMED numeric vector of ranking statistics "
            "SORTED DECREASING (names are gene IDs) ;; "
            "TERM2GENE=Two-column data frame mapping term ID to gene ID ;; "
            "minGSSize / maxGSSize=Bounds on gene set size for testing ;; "
            "pvalueCutoff=GSEA permutation p-value cutoff\n"
            "- alternatives: clusterprofiler=Use this for discrete-list ORA instead "
            "of ranked-list GSEA ;; "
            "fgsea=Faster preranked GSEA implementation, can run within the same "
            "workflow ;; "
            "CAMERA / ROAST=Linear-model-based alternatives that work on the "
            "original expression matrix instead of a precomputed rank\n"
            "- when_to_use: When you have the FULL ranked DE result (every measured "
            "gene with a statistic, not just significant hits) and want to detect "
            "coordinated pathway shifts even when no single gene crosses the FDR "
            "threshold. The ranked-statistic vector is required.\n"
            "- pitfalls: Passing an unranked gene list (use ORA variant instead) ;; "
            "Forgetting to sort DECREASING — clusterProfiler's gseGO assumes the "
            "rank vector is already sorted ;; "
            "Using p-values directly as the ranking statistic without signing them "
            "by direction of effect (mixes up- and down-regulated signals)"
        ),
    },
}


def backup_rows(con: sqlite3.Connection, names: list[str], path: Path) -> None:
    cur = con.execute(
        f"SELECT name, description, annotation_v2, annotation_v2_at "
        f"FROM workflows WHERE name IN ({','.join('?'*len(names))})",
        names,
    )
    rows = [dict(zip([c[0] for c in cur.description], r)) for r in cur.fetchall()]
    path.write_text(json.dumps(rows, indent=2, default=str))
    print(f"  backed up {len(rows)} row(s) to {path}")


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--apply", action="store_true")
    p.add_argument("--dry-run", action="store_true")
    args = p.parse_args()
    if not (args.apply or args.dry_run):
        p.error("pass --dry-run or --apply")

    if not DB.exists():
        print(f"DB not found: {DB}", file=sys.stderr)
        return 2

    names = list(UPDATES.keys())
    backup_path = DB.parent / f"differentiate_ambiguous_backup_{time.strftime('%Y%m%dT%H%M%S')}.json"

    con = sqlite3.connect(DB)
    try:
        # Show before-state
        for name in names:
            row = con.execute(
                "SELECT length(description) AS d, length(coalesce(annotation_v2,'')) AS a "
                "FROM workflows WHERE name=?", (name,)
            ).fetchone()
            if row is None:
                print(f"  MISSING in DB: {name}")
                return 2
            print(f"  before  {name:50}  desc={row[0]:5}  ann_v2={row[1]:5}")

        if args.dry_run:
            print("\n(dry-run — no changes written)")
            return 0

        backup_rows(con, names, backup_path)

        with con:  # atomic transaction
            for name, fields in UPDATES.items():
                sets = ", ".join(f"{k}=?" for k in fields)
                sets += ", annotation_v2_at=?"
                values = list(fields.values()) + [time.strftime("%Y-%m-%dT%H:%M:%S")]
                values.append(name)
                con.execute(f"UPDATE workflows SET {sets} WHERE name=?", values)
                changed = con.total_changes
                print(f"  updated {name:50}  (running changes: {changed})")

        # Verify after-state
        for name in names:
            row = con.execute(
                "SELECT length(description), length(coalesce(annotation_v2,'')) "
                "FROM workflows WHERE name=?", (name,)
            ).fetchone()
            print(f"  after   {name:50}  desc={row[0]:5}  ann_v2={row[1]:5}")

        print(f"\nbackup at: {backup_path}")
        print("done.")
        return 0
    finally:
        con.close()


if __name__ == "__main__":
    sys.exit(main())
