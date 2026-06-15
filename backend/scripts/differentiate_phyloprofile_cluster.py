"""Differentiate the 8 phyloprofile_* sub-workflows.

Pre-state: 5 of 9 had description == "phyloprofile" (workflow name, not a
description — auto-extraction failure). All 9 shared identical
annotation_v2.when_to_use ('Use when analyzing presence-absence patterns…'),
copy-pasted from the parent Bioc package vignette.

Post-state: each sub-workflow has:
- description = the one-line role description from its .nf header
- annotation_v2.when_to_use = role-specific guidance
- key_parameters / pitfalls / alternatives kept from the shared annotation
  (those are genuinely package-level and apply to every sub-workflow)

Source-of-truth for the new descriptions: the // Bioconductor workflow: ...
header in each .nf file under backend/biomni_workflows/nextflow_nfcore/
subworkflows/bioconductor/phyloprofile/.

Usage:
    python scripts/differentiate_phyloprofile_cluster.py --dry-run
    python scripts/differentiate_phyloprofile_cluster.py --apply
"""
from __future__ import annotations

import argparse
import json
import sqlite3
import sys
import time
from pathlib import Path

DB = Path(__file__).resolve().parents[1] / "database" / "galaxy_ai_tools.db"

# Shared package-level annotation chunks reused across every sub-workflow.
_KEY_PARAMS = (
    "rankName=Taxonomic rank to collapse input taxa (e.g., \"class\", \"phylum\") ;; "
    "refTaxon=Reference taxon used to order species by increasing taxonomic distance ;; "
    "var1AggregateBy/var2AggregateBy=Method to aggregate additional variables when collapsing into supertaxa (e.g., \"max\", \"mean\") ;; "
    "var1Cutoff/var2Cutoff=Cutoff thresholds for the two additional variables ;; "
    "percentCutoff=Cutoff for the percentage of species present in a supertaxon ;; "
    "coorthologCutoffMax=Maximum allowed number of co-orthologs ;; "
    "coreCoverage=The percentage of taxa that must be present in the selected set for core gene identification"
)
_PITFALLS = (
    "Orthology inference is not error-free, and orthology does not guarantee functional equivalence ;; "
    "Downstream analysis results can change substantially upon filtering — run "
    "phyloprofile_distribution_analysis FIRST to choose var1Cutoff / var2Cutoff / percentCutoff thresholds"
)


def _annot(when_to_use: str, alternatives: str = "Other phyloprofile_* sub-workflows in this cluster cover orthogonal roles — see when_to_use to pick the right one") -> str:
    return (
        f"- key_parameters: {_KEY_PARAMS}\n"
        f"- alternatives: {alternatives}\n"
        f"- when_to_use: {when_to_use}\n"
        f"- pitfalls: {_PITFALLS}"
    )


UPDATES: dict[str, dict[str, str]] = {
    "phyloprofile": {
        "description": (
            "PhyloProfile umbrella workflow: process raw orthology input data, generate a "
            "phylogenetic profile (presence-absence matrix of genes/orthologs across taxa), "
            "and visualize it as an interactive heatmap. Entry point when you have raw "
            "orthology output and want the full end-to-end profile build + viz."
        ),
        "annotation_v2": _annot(
            "When you have RAW orthology output (e.g., from fDOG / OrthoFinder) and want "
            "the complete end-to-end PhyloProfile build: parse → score → collapse to "
            "supertaxa → heatmap visualization. Use the role-specific sub-workflows "
            "(core_gene_identification / distribution_analysis / etc.) once the profile "
            "is built and you want a focused downstream analysis."
        ),
    },
    "phyloprofile_core_gene_identification": {
        "description": (
            "Identify CORE genes shared among a selected set of taxa from a processed "
            "phylogenetic profile (sortInputTaxa → count supertaxon presence → getCoreGene). "
            "Input: processed_profile.RData. Output: list of core gene IDs."
        ),
        "annotation_v2": _annot(
            "When you have a processed phylogenetic profile (.RData) AND a chosen set of "
            "taxa, and you want the subset of genes present in coreCoverage % of those taxa. "
            "Typical downstream of `phyloprofile`. Used to derive a taxon-specific core "
            "gene set (e.g., 'core eukaryotic genes', 'core mammalian genes')."
        ),
    },
    "phyloprofile_distribution_analysis": {
        "description": (
            "Plot the distribution of the integrated annotation layers (var1, var2) across "
            "the profile to help choose filtering thresholds. "
            "Input: raw_profile.txt. Output: distribution ggplot(s)."
        ),
        "annotation_v2": _annot(
            "EARLY in the workflow, BEFORE setting var1Cutoff / var2Cutoff / percentCutoff. "
            "Visualises the actual distribution of the per-ortholog variables (FAS score, "
            "%-identity, etc.) so you can pick principled thresholds rather than guess. "
            "Skip only if you already know the thresholds from a prior run."
        ),
    },
    "phyloprofile_domain_architecture_plot": {
        "description": (
            "Generate a protein domain architecture plot for a single gene of interest "
            "alongside its orthologs across taxa. Single-gene view (use _plotting variant "
            "for batch). Input: domain_annotation.txt."
        ),
        "annotation_v2": _annot(
            "When you have ONE gene of interest and want to compare its protein domain "
            "structure to orthologs in other species (find domain gain / loss events). "
            "Use phyloprofile_domain_architecture_plotting when you want to render the "
            "same plot for a BATCH of genes (one-per-page PDF)."
        ),
    },
    "phyloprofile_domain_architecture_plotting": {
        "description": (
            "Batch variant of domain architecture plotting: parse domain input and render "
            "domain architecture plots for many genes of interest in one run. "
            "Input: domain_annotation.txt with multiple gene IDs."
        ),
        "annotation_v2": _annot(
            "When you have MANY genes of interest and want one PDF page per gene comparing "
            "domain architecture across orthologs. For a single gene, use the simpler "
            "phyloprofile_domain_architecture_plot variant."
        ),
    },
    "phyloprofile_downstream_profile_analysis": {
        "description": (
            "Umbrella downstream-analysis orchestrator: runs profile clustering + gene age "
            "estimation + core gene identification + group comparison together on a "
            "processed profile."
        ),
        "annotation_v2": _annot(
            "When you want ALL major downstream analyses (clustering + gene age + core "
            "genes + group comparison) in a single chain. For a focused single-analysis "
            "use the dedicated sub-workflow (phyloprofile_profile_clustering, "
            "phyloprofile_gene_age_estimation, phyloprofile_core_gene_identification, "
            "phyloprofile_group_comparison)."
        ),
    },
    "phyloprofile_gene_age_estimation": {
        "description": (
            "Estimate the evolutionary age of each gene from a phylogenetic profile via the "
            "Last Common Ancestor (LCA) algorithm. Input: processed_profile.RData. "
            "Output: gene-age table."
        ),
        "annotation_v2": _annot(
            "When you have a processed profile and want to date each gene by its LCA "
            "(phylostratigraphy). Output is a per-gene evolutionary age estimate suitable "
            "for plotting age distributions or correlating age with expression / "
            "function."
        ),
    },
    "phyloprofile_group_comparison": {
        "description": (
            "Statistically compare the distribution of additional ortholog variables "
            "(FAS score, %-identity, etc.) between an IN-GROUP and OUT-GROUP of taxa. "
            "Input: raw_profile.txt + in-group taxon list."
        ),
        "annotation_v2": _annot(
            "When you have two taxonomic groups (in-group vs out-group) AND a profile "
            "annotated with extra per-ortholog variables, and you want to test whether "
            "those variables differ systematically between the groups (compareTaxonGroups). "
            "Common use: 'are orthologs in mammals more conserved than in fish for these "
            "genes?'"
        ),
    },
    "phyloprofile_profile_clustering": {
        "description": (
            "Cluster genes by similarity of their phylogenetic profiles (presence-absence "
            "distance) and plot a dendrogram. "
            "Input: processed_profile.RData. Output: cluster assignments + dendrogram."
        ),
        "annotation_v2": _annot(
            "When you want to group genes whose presence-absence patterns across taxa are "
            "similar — typically to discover functional modules or co-evolved gene sets. "
            "Output is a dendrogram plus optional cluster IDs per gene."
        ),
    },
}


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
    backup_path = DB.parent / f"phyloprofile_cluster_backup_{time.strftime('%Y%m%dT%H%M%S')}.json"

    con = sqlite3.connect(DB)
    try:
        for name in names:
            row = con.execute(
                "SELECT length(description), length(coalesce(annotation_v2,'')) FROM workflows WHERE name=?",
                (name,),
            ).fetchone()
            if row is None:
                print(f"  MISSING in DB: {name}")
                return 2
            print(f"  before  {name:55}  desc={row[0]:4}  ann_v2={row[1]:5}")

        if args.dry_run:
            print("\n(dry-run — no changes written)")
            return 0

        cur = con.execute(
            f"SELECT name, description, annotation_v2 FROM workflows WHERE name IN ({','.join('?'*len(names))})",
            names,
        )
        backup = [dict(zip([c[0] for c in cur.description], r)) for r in cur.fetchall()]
        backup_path.write_text(json.dumps(backup, indent=2, default=str))
        print(f"  backed up {len(backup)} row(s) to {backup_path}")

        with con:
            now = time.strftime("%Y-%m-%dT%H:%M:%S")
            for name, fields in UPDATES.items():
                con.execute(
                    "UPDATE workflows SET description=?, annotation_v2=?, annotation_v2_at=? WHERE name=?",
                    (fields["description"], fields["annotation_v2"], now, name),
                )
                print(f"  updated {name}")

        for name in names:
            row = con.execute(
                "SELECT length(description), length(coalesce(annotation_v2,'')) FROM workflows WHERE name=?",
                (name,),
            ).fetchone()
            print(f"  after   {name:55}  desc={row[0]:4}  ann_v2={row[1]:5}")

        # No two workflows should now share identical annotation_v2 within the cluster.
        dup = con.execute(
            f"SELECT count(*) FROM (SELECT annotation_v2 FROM workflows WHERE name IN ({','.join('?'*len(names))}) GROUP BY annotation_v2 HAVING count(*) > 1)",
            names,
        ).fetchone()[0]
        print(f"\n  duplicate annotation_v2 within cluster after apply: {dup} (should be 0)")
        print("done.")
        return 0
    finally:
        con.close()


if __name__ == "__main__":
    sys.exit(main())
