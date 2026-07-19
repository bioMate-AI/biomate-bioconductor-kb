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
    # ── Wave 2: 12 additional workflows indexed 2026-07-18 ───────────────────
    {
        "name":        "alphafold",
        "filename":    "nf-core-workflows/modules/biomate-ai-tools/alphafold/main.nf",
        "description": (
            "Retrieves pre-computed protein structures from the AlphaFold EBI "
            "database (200M+ structures, v4 model) via UniProt accession, or "
            "formats input JSON for submission to the free AlphaFold 3 Server "
            "(20 jobs/day limit) for new predictions including complexes. "
            "Input: UniProt accession ID (for DB lookup) or FASTA (for AF3 server). "
            "Output: PDB structure file, optional mmCIF, and per-residue confidence JSON."
        ),
        "annotation":  (
            "UniProt ID or FASTA → PDB + confidence JSON (AlphaFold DB v4 / AF3 Server)"
        ),
        "tags":        (
            "alphafold,alphafold2,alphafold3,structure prediction,protein folding,"
            "ebi database,uniprot,precomputed structure,confidence,plddt"
        ),
        "domain":      "structural_biology",
        "category":    "Structure Prediction",
        "docker_image":"biomate/biomni-tools:latest",
        "input_types": ["fasta", "uniprot_id"],
        "output_types":["pdb", "cif", "json"],
        "step_count":  2,
        "tools_used":  "AlphaFold DB v4, AlphaFold 3 Server (EBI)",
    },
    {
        "name":        "boltz",
        "filename":    "nf-core-workflows/modules/biomate-ai-tools/boltz/main.nf",
        "description": (
            "Boltz-2 is a GPU-based protein-ligand structure prediction model that "
            "jointly predicts 3D conformations and binding affinities. It accepts "
            "a FASTA file plus an optional ligand SDF, and outputs predicted PDB/CIF "
            "structures and affinity JSON. Requires 16–40 GB VRAM. "
            "Input: FASTA + optional ligand SDF. "
            "Output: PDB/CIF structures + binding affinity JSON."
        ),
        "annotation":  (
            "FASTA + optional ligand SDF → PDB/CIF structures + binding affinity JSON (Boltz-2)"
        ),
        "tags":        (
            "boltz,boltz2,protein-ligand,structure prediction,binding affinity,"
            "gpu,deep learning,molecular complex,cif,pdb"
        ),
        "domain":      "structural_biology",
        "category":    "Structure Prediction",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/boltz:nextflow",
        "input_types": ["fasta", "sdf"],
        "output_types":["pdb", "cif", "json"],
        "step_count":  1,
        "tools_used":  "Boltz-2",
    },
    {
        "name":        "chai1",
        "filename":    "nf-core-workflows/modules/biomate-ai-tools/chai1/main.nf",
        "description": (
            "Chai-1 is a multi-modal biomolecular structure prediction model supporting "
            "proteins, DNA, RNA, ligands (SDF or SMILES), and glycans in a single unified "
            "architecture. Requires 24–80 GB VRAM GPU. "
            "Input: FASTA (with optional ligand SDF/SMILES). "
            "Output: PDB/CIF structures and confidence score JSON."
        ),
        "annotation":  (
            "FASTA + optional ligand SDF/SMILES → PDB/CIF structures + scores JSON (Chai-1)"
        ),
        "tags":        (
            "chai1,chai,multimodal,structure prediction,protein-ligand,dna,rna,"
            "glycan,gpu,deep learning,biomolecular complex"
        ),
        "domain":      "structural_biology",
        "category":    "Structure Prediction",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/chai1:nextflow",
        "input_types": ["fasta", "sdf", "smiles"],
        "output_types":["pdb", "cif", "json"],
        "step_count":  1,
        "tools_used":  "Chai-1 (Chai Discovery)",
    },
    {
        "name":        "cryo_heterogeneity",
        "filename":    "nf-core-workflows/modules/biomate-ai-tools/cryo_heterogeneity/main.nf",
        "description": (
            "Resolves continuous conformational heterogeneity in cryo-EM particle stacks "
            "using cryoDRGN (VAE-based latent representation), then performs UMAP + k-means "
            "clustering to identify representative conformational states, and scans the "
            "ensemble of reconstructed volumes for druggable binding pockets using fpocket. "
            "Input: particle MRCS stack (STAR format) + CTF/poses PKL files. "
            "Output: heterogeneity report JSON with conformational entropy, population "
            "fractions, and per-state druggability scores."
        ),
        "annotation":  (
            "Particles STAR + CTF/poses PKL → conformational ensemble + pocket scan JSON "
            "(cryoDRGN + fpocket)"
        ),
        "tags":        (
            "cryodrgn,cryo-em,conformational heterogeneity,vae,latent space,"
            "fpocket,druggable pocket,structural biology,umap,kmeans,mrcs"
        ),
        "domain":      "structural_biology",
        "category":    "Cryo-EM Analysis",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/cryo-heterogeneity-nf:latest",
        "input_types": ["mrcs", "star", "pkl"],
        "output_types":["json", "mrc"],
        "step_count":  4,
        "tools_used":  "cryoDRGN, fpocket, UMAP",
    },
    {
        "name":        "drugclip",
        "filename":    "nf-core-workflows/modules/biomate-ai-tools/drugclip/main.nf",
        "description": (
            "Ultra-fast contrastive-learning virtual drug screening that is orders of "
            "magnitude faster than traditional docking. Can run locally against a custom "
            "compound library (SDF or SMILES) given a protein FASTA, or query the "
            "pre-computed DrugCLIP API database via UniProt ID. "
            "Input: protein FASTA + compound library SDF/SMILES (local), or UniProt ID (API). "
            "Output: scored compound CSV with top hits."
        ),
        "annotation":  (
            "Protein FASTA + compounds SDF → scored hits CSV (DrugCLIP virtual screening)"
        ),
        "tags":        (
            "drugclip,virtual screening,drug discovery,contrastive learning,"
            "compound library,protein-ligand,ultra-fast,smiles,sdf,uniprot"
        ),
        "domain":      "drug_discovery",
        "category":    "Virtual Screening",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/drugclip:nextflow",
        "input_types": ["fasta", "sdf", "smiles"],
        "output_types":["csv", "json"],
        "step_count":  2,
        "tools_used":  "DrugCLIP (Contrastive Learning Virtual Screening)",
    },
    {
        "name":        "profam",
        "filename":    "nf-core-workflows/modules/biomate-ai-tools/profam/main.nf",
        "description": (
            "ProFam is a protein family language model for variant fitness scoring and "
            "novel sequence generation conditioned on a protein family multiple sequence "
            "alignment (MSA) or reference FASTA. Score variants against family fitness "
            "landscape, or sample new sequences at a given temperature. "
            "Input: conditioning FASTA (family MSA or reference) + candidate sequences "
            "FASTA/CSV (for scoring) or MSA alone (for generation). "
            "Output: ranked fitness scores CSV or generated FASTA."
        ),
        "annotation":  (
            "Family MSA FASTA + candidates → fitness scores CSV or generated sequences FASTA (ProFam)"
        ),
        "tags":        (
            "profam,protein language model,variant fitness,sequence design,"
            "protein engineering,msa,directed evolution,zero-shot,generative model,fitness landscape"
        ),
        "domain":      "proteomics",
        "category":    "Protein Engineering",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/profam:nextflow",
        "input_types": ["fasta", "csv"],
        "output_types":["csv", "fasta"],
        "step_count":  2,
        "tools_used":  "ProFam (Protein Family Language Model)",
    },
    {
        "name":        "protein_dynamics",
        "filename":    "nf-core-workflows/modules/biomate-ai-tools/protein_dynamics/main.nf",
        "description": (
            "Generates a conformational ensemble for a protein using BioEmu-1 "
            "(GPU-based generative model) or an MDAnalysis Gaussian perturbation fallback, "
            "then detects cryptic binding pockets across the ensemble using PocketMiner and "
            "fpocket, and finally produces a UMAP/PCA projection of the ensemble with "
            "RMSD/Rg distributions and a summary report. "
            "Input: PDB or FASTA. "
            "Output: ensemble tarball, per-frame pocket JSON, UMAP PNG, and summary JSON."
        ),
        "annotation":  (
            "PDB or FASTA → conformational ensemble + cryptic pocket scan + UMAP plot "
            "(BioEmu + PocketMiner + fpocket)"
        ),
        "tags":        (
            "bioemu,protein dynamics,conformational ensemble,cryptic pocket,"
            "pocketminer,fpocket,mdanalysis,umap,rmsd,radius of gyration,structural biology"
        ),
        "domain":      "structural_biology",
        "category":    "Protein Dynamics",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/protein-dynamics-nf:v1.0.8",
        "input_types": ["pdb", "fasta"],
        "output_types":["json", "png", "pdb"],
        "step_count":  3,
        "tools_used":  "BioEmu-1, PocketMiner, fpocket, MDAnalysis",
    },
    {
        "name":        "protrek",
        "filename":    "nf-core-workflows/modules/biomate-ai-tools/protrek/main.nf",
        "description": (
            "ProTrek is a trimodal protein search model (100× faster than Foldseek) that "
            "searches a large protein database by amino acid sequence, 3D structure, or "
            "free-text functional description. Also supports generating embeddings for "
            "custom databases. "
            "Input: query (sequence string, PDB path, or text description) + query type. "
            "Output: ranked hits JSON and TSV with UniProt IDs, scores, and function annotations."
        ),
        "annotation":  (
            "Sequence / PDB / text query → ranked UniProt hits JSON + TSV (ProTrek trimodal search)"
        ),
        "tags":        (
            "protrek,trimodal search,protein search,sequence search,structure search,"
            "text search,uniprot,embedding,protein retrieval,fast search,language model"
        ),
        "domain":      "proteomics",
        "category":    "Protein Search",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/protrek:nextflow",
        "input_types": ["fasta", "pdb", "txt"],
        "output_types":["json", "tsv", "pt"],
        "step_count":  2,
        "tools_used":  "ProTrek (Trimodal Protein Search)",
    },
    {
        "name":        "scfv-pmpnn",
        "filename":    "nf-core-workflows/modules/biomate-ai-tools/scfv-pmpnn/main.nf",
        "description": (
            "AI-powered single-chain variable fragment (scFv) antibody sequence design "
            "using ProteinMPNN, followed by optional AlphaFold2 structure validation. "
            "Given a target antigen PDB, generates a pool of designed scFv sequences scored "
            "by ProteinMPNN log-likelihood, then predicts structures and confidence for the "
            "top designs. "
            "Input: target antigen PDB. "
            "Output: designed scFv FASTA, scores CSV, and optional predicted PDB structures."
        ),
        "annotation":  (
            "Target antigen PDB → designed scFv FASTA + scores CSV + predicted PDB structures "
            "(ProteinMPNN + AF2)"
        ),
        "tags":        (
            "scfv,antibody design,proteinmpnn,alphafold2,protein design,immunology,"
            "single-chain antibody,antigen,inverse folding,sequence design"
        ),
        "domain":      "immunology",
        "category":    "Antibody Design",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/scfv-pmpnn:nextflow",
        "input_types": ["pdb"],
        "output_types":["fasta", "csv", "pdb"],
        "step_count":  2,
        "tools_used":  "ProteinMPNN, AlphaFold2",
    },
    {
        "name":        "sirna_design",
        "filename":    "nf-core-workflows/modules/biomate-ai-tools/sirna_design/main.nf",
        "description": (
            "Generates and scores siRNA candidates from an input mRNA sequence using the "
            "industry-standard Ui-Tei 2004 (4 criteria) and Reynolds 2004 (8 criteria) "
            "scoring rules plus thermodynamic asymmetry analysis (Schwarz/Khvorova 2003). "
            "Scans all 19-, 20-, and 21-mer windows, filters by GC content (30–52% default), "
            "ranks by composite score (max 13), and assigns efficacy tiers A–D. "
            "Input: FASTA file or raw mRNA sequence. "
            "Output: ranked candidates CSV, scoring summary JSON, and design report."
        ),
        "annotation":  (
            "mRNA FASTA or sequence → ranked siRNA candidates CSV + scoring JSON + report "
            "(Ui-Tei/Reynolds criteria)"
        ),
        "tags":        (
            "sirna,sirna design,rnai,mrna,uitei,reynolds,risc,gc content,"
            "thermodynamic asymmetry,oligonucleotide design,gene silencing"
        ),
        "domain":      "other",
        "category":    "RNA Therapeutics",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86",
        "input_types": ["fasta", "txt"],
        "output_types":["csv", "json", "txt"],
        "step_count":  1,
        "tools_used":  "Ui-Tei/Reynolds siRNA scoring rules",
    },
    {
        "name":        "state",
        "filename":    "nf-core-workflows/modules/biomate-ai-tools/state/main.nf",
        "description": (
            "STATE (arc-state) is a virtual cell model that predicts single-cell "
            "transcriptomic responses to perturbations including gene knockdown, drug "
            "treatment, and CRISPR edits. Takes an AnnData h5ad file with scRNA-seq data "
            "and a perturbation column label, and outputs a simulated h5ad with predicted "
            "post-perturbation expression profiles. Also supports generating latent cell "
            "embeddings. "
            "Input: AnnData h5ad. "
            "Output: simulated h5ad + optional predictions CSV."
        ),
        "annotation":  (
            "AnnData h5ad + perturbation labels → simulated post-perturbation h5ad "
            "(STATE virtual cell model)"
        ),
        "tags":        (
            "state,virtual cell,perturbation,single cell,scrna-seq,anndata,"
            "crispr,gene knockdown,drug response,transcriptomics,h5ad"
        ),
        "domain":      "single_cell",
        "category":    "Virtual Cell Modeling",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/state:nextflow",
        "input_types": ["h5ad"],
        "output_types":["h5ad", "csv"],
        "step_count":  2,
        "tools_used":  "STATE (arc-state virtual cell model)",
    },
    {
        "name":        "syncraft",
        "filename":    "nf-core-workflows/modules/biomate-ai-tools/syncraft/main.nf",
        "description": (
            "LLM-powered retrosynthesis planning tool that uses Gemini to propose "
            "multi-step synthesis routes for drug molecules given a SMILES string. "
            "Supports single-molecule and batch mode. Requires GEMINI_API_KEY. "
            "Input: SMILES string (single) or SMILES list file (batch). "
            "Output: synthesis route JSON + human-readable text plan."
        ),
        "annotation":  (
            "SMILES → synthesis route JSON + text plan (SynCraft LLM retrosynthesis, Gemini)"
        ),
        "tags":        (
            "syncraft,retrosynthesis,synthesis planning,smiles,drug discovery,"
            "medicinal chemistry,llm,gemini,ai chemistry,route planning"
        ),
        "domain":      "drug_discovery",
        "category":    "Chemical Synthesis",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/syncraft:nextflow",
        "input_types": ["smiles", "txt"],
        "output_types":["json", "txt", "csv"],
        "step_count":  2,
        "tools_used":  "SynCraft (Gemini-powered retrosynthesis)",
    },
    # ── Wave 1: 6 workflows indexed earlier ─────────────────────────────────
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
