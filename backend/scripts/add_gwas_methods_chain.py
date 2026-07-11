#!/usr/bin/env python3
"""Insert workflow rows for the shared GWAS methods stack.

Covers tools used by both Zhi lab (Z01 TorchGWAS / Nat Commun 2026) and
Zhao lab (ZZ02 scGWAS / Genome Biology 2022):

  magma_gene_analysis  — MAGMA v1.10 gene-based GWAS analysis
  metal_meta_analysis  — METAL multi-cohort meta-analysis
  ldsc_heritability    — LDSC SNP-heritability + cross-trait rg

Also inserts a workflow_chain for the full Z01 pre+post stack:
  z01_gwas_methods_chain  (METAL → MAGMA → TorchGWAS → LDSC)

Idempotent (ON CONFLICT / check-before-insert).
"""
from __future__ import annotations
import json, os, sqlite3, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DB_PATH = os.path.join(ROOT, "backend", "database", "galaxy_ai_tools.db")

WORKFLOWS = [
    {
        "name": "magma_gene_analysis",
        "domain": "population_genetics",
        "description": (
            "MAGMA v1.10 gene-based GWAS analysis. 3-phase: SNP annotation → "
            "per-gene Z-statistics → box-cox transform for scGWAS input. "
            "Bakes g1000_eur LD reference + NCBI37/38 gene location files. "
            "Emits .magma_boxcox.txt compatible with scgwas_immune_cell. "
            "Wraps ctg.cncr.nl/software/magma (academic freeware). "
            "Used by Zhao lab Genome Biology 2022 (PMC9575201) and "
            "Zhi lab Nat Commun 2026 (PMC12458571)."
        ),
        "tags": ["gwas", "magma", "gene_analysis", "population_genetics",
                 "zhao_lab", "zhi_lab"],
        "step_count": 3,
    },
    {
        "name": "metal_meta_analysis",
        "domain": "population_genetics",
        "description": (
            "METAL multi-cohort GWAS meta-analysis. 2-phase: prep cohort files + "
            "write METAL script → execute METAL → combined sumstats. "
            "Supports STDERR (inverse-variance) and SAMPLESIZE schemes. "
            "Feeds into magma_gene_analysis and ldsc_heritability. "
            "Wraps github.com/statgen/METAL (MIT, Willer et al. Bioinformatics 2010). "
            "Used in Zhi lab Nat Commun 2026 (PMC12458571) Methods."
        ),
        "tags": ["gwas", "meta_analysis", "metal", "population_genetics", "zhi_lab"],
        "step_count": 2,
    },
    {
        "name": "ldsc_heritability",
        "domain": "population_genetics",
        "description": (
            "LDSC v1.0.1 SNP-heritability and LD score regression. 3-phase: "
            "munge sumstats → h² estimation → QC report with intercept + ratio flags. "
            "Bakes eur_w_ld_chr LD scores (22 chr) + w_hm3.snplist. "
            "Wraps github.com/bulik/ldsc (GPL-3.0, Bulik-Sullivan et al. Nat Genet 2015). "
            "Used in Zhi lab Nat Commun 2026 (PMC12458571) to validate GWAS calibration."
        ),
        "tags": ["gwas", "heritability", "ldsc", "population_genetics", "zhi_lab"],
        "step_count": 3,
    },
]

CHAINS = [
    {
        "name": "z01_gwas_methods_chain",
        "display_name": "Full GWAS methods stack — Z01 (METAL → MAGMA → TorchGWAS → LDSC)",
        "domain": "population_genetics",
        "description": (
            "Complete Zhi-lab GWAS methods stack as described in Nat Commun 2026 "
            "(PMC12458571): (1) METAL meta-analyzes cohort sumstats, (2) MAGMA converts "
            "SNP-level results to gene-level Z-scores, (3) TorchGWAS runs GPU-accelerated "
            "GWAS on raw genotypes, (4) LDSC estimates SNP-heritability and validates "
            "calibration. All 4 tools are paper-faithful wraps."
        ),
        "wfs": [
            "metal_meta_analysis",
            "magma_gene_analysis",
            "torchgwas_udip_phenotype_scan",
            "ldsc_heritability",
        ],
        "roles": [
            "zhi_lab_meta_analysis",
            "zhi_lab_gene_analysis",
            "zhi_lab_gwas_scan",
            "zhi_lab_heritability_qc",
        ],
        "queries": [
            "Run the full Z01 GWAS methods stack",
            "meta-analyze cohorts then GWAS with TorchGWAS and check heritability",
            "METAL + MAGMA + TorchGWAS + LDSC pipeline Zhi lab style",
            "SNP heritability and gene-based tests from UK Biobank imaging phenotypes",
        ],
        "tags": ["gwas", "meta_analysis", "magma", "torchgwas", "ldsc",
                 "population_genetics", "zhi_lab", "multi_step"],
    },
]


def _nf_path(wf): return f"nf-core-workflows/modules/biomate-ai-tools/{wf}/main.nf"


def _ensure_workflow_row(cur, w):
    cur.execute("PRAGMA table_info(workflows)")
    cols = {c[1] for c in cur.fetchall()}
    if cur.execute("SELECT 1 FROM workflows WHERE name=?", (w["name"],)).fetchone():
        return
    row = {
        "name": w["name"],
        "filename": _nf_path(w["name"]),
        "domain": w["domain"],
        "description": w["description"],
        "workflow_json": json.dumps({
            "name": w["name"], "format-version": "0.1",
            "steps": {}, "tags": w["tags"], "annotation": w["description"],
        }),
        "format": "nextflow",
        "source": "biomate-ai-tools",
        "category": "biomate-ai-tools",
        "step_count": w["step_count"],
        "tags": json.dumps(w["tags"]),
    }
    fields = [f for f in row if f in cols]
    cur.execute(
        f"INSERT INTO workflows ({','.join(fields)}) VALUES ({','.join('?'*len(fields))})",
        [row[f] for f in fields],
    )
    print(f"  + workflow: {w['name']}")


def main():
    if not os.path.exists(DB_PATH):
        print(f"DB not found: {DB_PATH}", file=sys.stderr)
        return 1
    inserted = skipped = 0
    with sqlite3.connect(DB_PATH) as conn:
        cur = conn.cursor()
        for w in WORKFLOWS:
            _ensure_workflow_row(cur, w)
        cur.execute("PRAGMA table_info(workflow_chains)")
        cols = {c[1] for c in cur.fetchall()}
        for c in CHAINS:
            if cur.execute("SELECT id FROM workflow_chains WHERE name=?", (c["name"],)).fetchone():
                print(f"  skip: {c['name']}"); skipped += 1; continue
            steps = [
                {"order": i+1, "workflow_name": w, "role": r,
                 "params_template": {}, "nextflow_path": _nf_path(w)}
                for i, (w, r) in enumerate(zip(c["wfs"], c["roles"]))
            ]
            row = {
                "name": c["name"], "display_name": c["display_name"],
                "domain": c["domain"], "description": c["description"],
                "steps": steps, "connections": [],
                "required_inputs": [{"name": "input_json", "type": "json"}],
                "expected_outputs": [{"name": "report_json", "type": "json"},
                                     {"name": "report_md", "type": "markdown"}],
                "example_queries": c["queries"],
                "tags": c["tags"],
            }
            fields = [f for f in row if f in cols]
            values = [json.dumps(row[f]) if not isinstance(row[f], str) else row[f]
                      for f in fields]
            cur.execute(
                f"INSERT INTO workflow_chains ({','.join(fields)}) VALUES ({','.join('?'*len(fields))})",
                values,
            )
            print(f"  + chain: {c['name']} → id={cur.lastrowid}")
            inserted += 1
        conn.commit()
    print(f"\ninserted={inserted} skipped={skipped}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
