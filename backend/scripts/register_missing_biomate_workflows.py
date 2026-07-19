#!/usr/bin/env python3
"""
register_missing_biomate_workflows.py

Registers 6 BioMate AI tool Nextflow workflows that are on disk but absent
from the workflows DB: af3, esmfold, fuma_functional_annotation,
magma_gene_based_test, gcta_mlma, ai_marrvel.

Also rebuilds FTS for the workflows table.

Usage:
    python3 scripts/register_missing_biomate_workflows.py \
        [--db /path/to/galaxy_ai_tools.db]
"""
import argparse
import hashlib
import sqlite3
from pathlib import Path

REPO_ROOT = Path(__file__).parent.parent
NF_BASE   = REPO_ROOT / "nf-core-workflows" / "modules" / "biomate-ai-tools"
DB_DEFAULT = REPO_ROOT / "database" / "galaxy_ai_tools.db"

WORKFLOWS = [
    {
        "name":        "af3",
        "filename":    "nf-core-workflows/modules/biomate-ai-tools/af3/main.nf",
        "description": (
            "AlphaFold 3 structure prediction pipeline. Predicts 3D structures of "
            "proteins, nucleic acids, small molecules, and covalent modifications "
            "via the AF3 unified diffusion model. State-of-the-art accuracy for "
            "protein-ligand and protein-nucleic acid complexes. "
            "Input: AF3 fold_input.json (sequences + entity types). "
            "Output: predicted .cif structures, per-residue confidence (pLDDT), "
            "PAE matrix, ranking_scores.json."
        ),
        "annotation":  (
            "AlphaFold 3 (Google DeepMind). Input: JSON fold_input. "
            "Output: mmCIF, pLDDT/PAE, ranking scores."
        ),
        "tags":        (
            "alphafold3,af3,alphafold,structure prediction,protein folding,"
            "protein-ligand,protein-nucleic acid,diffusion model,deepmind"
        ),
        "domain":      "structural_biology",
        "category":    "Structure Prediction",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/af3-nf:v1.0.1",
        "input_types": ["json"],
        "output_types":["cif", "json"],
        "step_count":  2,
        "tools_used":  "AlphaFold 3",
    },
    {
        "name":        "esmfold",
        "filename":    "nf-core-workflows/modules/biomate-ai-tools/esmfold/main.nf",
        "description": (
            "Fast protein structure prediction using ESMFold via the ESM Metagenomic "
            "Atlas free API (no API key required, max 400 residues). Single forward "
            "pass — ~10s per protein — compared to hours for physics-based methods. "
            "Good for rapid structure screening of short sequences. "
            "Input: FASTA file. "
            "Output: predicted .pdb structure."
        ),
        "annotation":  (
            "ESMFold API-based structure prediction. Free, no key. Max 400 aa. "
            "Input: FASTA. Output: PDB."
        ),
        "tags":        (
            "esmfold,esm,protein folding,structure prediction,language model,"
            "fast folding,meta,sequence-only,no msa required"
        ),
        "domain":      "structural_biology",
        "category":    "Structure Prediction",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomni-lite:latest",
        "input_types": ["fasta"],
        "output_types":["pdb"],
        "step_count":  1,
        "tools_used":  "ESMFold (Meta ESM API)",
    },
    {
        "name":        "fuma_functional_annotation",
        "filename":    "nf-core-workflows/modules/biomate-ai-tools/fuma_functional_annotation/main.nf",
        "description": (
            "GWAS functional annotation pipeline using the FUMA (Functional Mapping "
            "and Annotation) web platform. Submits GWAS summary statistics to the "
            "FUMA SNP2GENE endpoint, polls for completion, downloads results, and "
            "parses: genomic risk loci, MAGMA gene-based test, MAGMA gene-set "
            "enrichment analysis (GSA). "
            "Reference: Watanabe et al. 2017 Nat Commun 8:1826. "
            "Input: GWAS sumstats (SNP CHR BP A1 A2 P columns). "
            "Output: fuma_report.json + fuma_report.md with loci, gene hits, "
            "pathway enrichment."
        ),
        "annotation":  (
            "FUMA SNP2GENE functional annotation of GWAS sumstats. "
            "Includes MAGMA gene-based + GSA. Input: sumstats. Output: JSON+MD report."
        ),
        "tags":        (
            "fuma,gwas,functional annotation,snp2gene,magma,gene set enrichment,"
            "genomic risk loci,population genetics,snp annotation,pathway"
        ),
        "domain":      "population_genetics",
        "category":    "GWAS Analysis",
        "docker_image":"biomate/biomni-tools:latest",
        "input_types": ["tsv", "txt"],
        "output_types":["json", "md"],
        "step_count":  4,
        "tools_used":  "FUMA SNP2GENE, MAGMA",
    },
    {
        "name":        "magma_gene_based_test",
        "filename":    "nf-core-workflows/modules/biomate-ai-tools/magma_gene_based_test/main.nf",
        "description": (
            "MAGMA gene-based GWAS test pipeline. Maps GWAS SNPs to genes with a "
            "35 kb upstream / 10 kb downstream window, then runs the MAGMA gene-based "
            "association test against a 1000G reference panel. Outputs ranked gene "
            "hits with Bonferroni-corrected p-values. "
            "Reference: de Leeuw et al. 2015 PLOS Comput Biol 11(4):e1004219. "
            "Input: GWAS sumstats (SNP P columns + sample size), reference panel bfile. "
            "Output: magma_report.json + magma_report.md with top gene hits."
        ),
        "annotation":  (
            "MAGMA gene-based GWAS test. SNP→gene mapping + gene association test. "
            "Input: sumstats + PLINK bfile. Output: ranked gene hits JSON+MD."
        ),
        "tags":        (
            "magma,gene-based test,gwas,snp to gene,association test,"
            "population genetics,1000 genomes,bonferroni,gene mapping"
        ),
        "domain":      "population_genetics",
        "category":    "GWAS Analysis",
        "docker_image":"biomate/biomni-tools:latest",
        "input_types": ["tsv", "txt"],
        "output_types":["json", "md"],
        "step_count":  4,
        "tools_used":  "MAGMA v1.10",
    },
    {
        "name":        "gcta_mlma",
        "filename":    "nf-core-workflows/modules/biomate-ai-tools/gcta_mlma/main.nf",
        "description": (
            "GCTA mixed linear model association (MLMA) pipeline for genome-wide "
            "association studies. Builds a genetic relationship matrix (GRM) from "
            "PLINK genotype files, then runs MLMA-LOCO (leaving one chromosome out) "
            "to control for population stratification. Outputs per-SNP association "
            "statistics with genomic inflation correction. "
            "Reference: Yang et al. 2011 Am J Hum Genet 88:76. "
            "Input: PLINK .bed/.bim/.fam triplet + phenotype file. "
            "Output: gcta_report.json + gcta_report.md with top SNPs, QQ plot data, "
            "lambda GC."
        ),
        "annotation":  (
            "GCTA MLMA mixed model GWAS. GRM + MLMA-LOCO. "
            "Input: PLINK bfile + pheno. Output: top SNPs, lambda GC, JSON+MD."
        ),
        "tags":        (
            "gcta,mlma,loco,mixed model,gwas,genetic relationship matrix,grm,"
            "population stratification,association test,population genetics,snp"
        ),
        "domain":      "population_genetics",
        "category":    "GWAS Analysis",
        "docker_image":"biomate/biomni-tools:latest",
        "input_types": ["bed", "bim", "fam", "txt"],
        "output_types":["json", "md"],
        "step_count":  4,
        "tools_used":  "GCTA v1.94",
    },
    {
        "name":        "ai_marrvel",
        "filename":    "nf-core-workflows/modules/biomate-ai-tools/ai_marrvel/main.nf",
        "description": (
            "AI-MARRVEL rare disease variant prioritization pipeline. Integrates "
            "multi-database evidence (ClinVar, OMIM, gnomAD, Orphanet, HGMD) with "
            "an ensemble ML model to rank candidate causal variants in exome/genome "
            "sequencing data. Designed for Mendelian disease diagnosis. "
            "Reference: Liu et al. 2023 NEJM AI 1(6) — 70% top-3 diagnostic accuracy "
            "on published rare disease cases. "
            "Input: annotated VCF (sarek+VEP output) + comma-separated HPO terms. "
            "Output: variant prioritization report JSON + ranked candidate list MD."
        ),
        "annotation":  (
            "AI-MARRVEL rare disease variant prioritization. VCF + HPO → ranked candidates. "
            "70% top-3 diagnostic accuracy (NEJM AI 2023)."
        ),
        "tags":        (
            "ai-marrvel,marrvel,rare disease,variant prioritization,exome,"
            "mendelian disease,hpo,clinvar,omim,gnomad,orphanet,ensemble ml,"
            "rare variant,diagnostic,phenotype-driven"
        ),
        "domain":      "rare_disease",
        "category":    "Variant Prioritization",
        "docker_image":"biomate/biomni-tools:latest",
        "input_types": ["vcf"],
        "output_types":["json", "md"],
        "step_count":  4,
        "tools_used":  "AI-MARRVEL (LiuzLab)",
    },
]


def workflow_hash(entry: dict) -> str:
    payload = f"{entry['name']}|{entry['filename']}|{entry['description']}"
    return hashlib.sha256(payload.encode()).hexdigest()[:16]


def rebuild_fts(conn: sqlite3.Connection) -> None:
    print("  Rebuilding workflows_fts …", end=" ")
    conn.execute("DELETE FROM workflows_fts")
    conn.execute("""
        INSERT INTO workflows_fts(rowid, name, description, annotation, tags, domain, tools_used)
        SELECT id, name, description, annotation, tags, domain, tools_used
        FROM workflows
    """)
    print("done.")


def register(db_path: Path) -> None:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    inserted = 0
    skipped  = 0

    for entry in WORKFLOWS:
        h = workflow_hash(entry)
        existing = conn.execute(
            "SELECT id FROM workflows WHERE name = ? OR workflow_hash = ?",
            (entry["name"], h),
        ).fetchone()
        if existing:
            print(f"  SKIP  {entry['name']} (already in DB, id={existing['id']})")
            skipped += 1
            continue

        nf_path = NF_BASE / entry["name"] / "main.nf"
        if not nf_path.exists():
            print(f"  WARN  {entry['name']} — main.nf not found at {nf_path}, skipping")
            skipped += 1
            continue

        nf_content = nf_path.read_text(encoding="utf-8")
        conn.execute(
            """
            INSERT INTO workflows
                (name, filename, description, annotation, tags, domain, category,
                 docker_image, input_types, output_types, step_count, tools_used,
                 format, executable, source, workflow_hash, workflow_json)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            """,
            (
                entry["name"],
                entry["filename"],
                entry["description"],
                entry["annotation"],
                entry["tags"],
                entry["domain"],
                entry["category"],
                entry["docker_image"],
                ",".join(entry.get("input_types", [])),
                ",".join(entry.get("output_types", [])),
                entry.get("step_count", 1),
                entry["tools_used"],
                "nextflow",
                1,
                "biomate-ai-tools",
                h,
                nf_content,
            ),
        )
        print(f"  ADD   {entry['name']}")
        inserted += 1

    conn.commit()
    rebuild_fts(conn)
    conn.commit()
    conn.close()
    print(f"\nDone: {inserted} inserted, {skipped} skipped.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", default=str(DB_DEFAULT))
    args = parser.parse_args()
    db_path = Path(args.db)
    if not db_path.exists():
        print(f"ERROR: DB not found at {db_path}")
        raise SystemExit(1)
    print(f"Registering missing BioMate AI tool workflows into {db_path}")
    register(db_path)
