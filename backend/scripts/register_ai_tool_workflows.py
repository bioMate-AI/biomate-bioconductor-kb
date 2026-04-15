#!/usr/bin/env python3
"""
register_ai_tool_workflows.py

Registers the 8 BioMate AI tool Nextflow workflows into the Galaxy workflows
table and rebuilds the FTS index. Run once after files are created; safe to
re-run (uses workflow_hash for idempotency).

Usage:
    python scripts/register_ai_tool_workflows.py [--db /path/to/galaxy_ai_tools.db]
"""

import argparse
import hashlib
import json
import sqlite3
import sys
from datetime import datetime
from pathlib import Path

REPO_ROOT = Path(__file__).parent.parent
NF_BASE   = REPO_ROOT / "biomni_workflows" / "nextflow_nfcore" / "subworkflows"

WORKFLOWS = [
    {
        "name":        "boltz_structure_prediction",
        "filename":    "structural_biology/boltz_structure_prediction/main.nf",
        "description": (
            "Biomolecular structure prediction using Boltz-2 (MIT licensed). "
            "Predicts structures of proteins, RNA, DNA, ligands, and protein-ligand complexes "
            "with binding affinity estimates. 1000x faster than physics-based FEP. "
            "Input: FASTA or YAML. Output: mmCIF/PDB structures, confidence scores."
        ),
        "annotation":  "Boltz-2 v2.2.1 structure prediction. Input: FASTA/YAML. Output: mmCIF, confidence JSON.",
        "tags":        "boltz,boltz2,structure prediction,protein folding,ligand binding,binding affinity,biomolecular",
        "domain":      "structural_biology",
        "category":    "Structure Prediction",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/boltz:latest",
        "input_types": ["fasta", "yaml"],
        "output_types":["mmcif", "pdb", "json"],
        "step_count":  3,
        "tools_used":  "Boltz-2",
    },
    {
        "name":        "chai1_structure_prediction",
        "filename":    "structural_biology/chai1_structure_prediction/main.nf",
        "description": (
            "Multi-modal biomolecular structure prediction using Chai-1 (Apache 2.0). "
            "Handles proteins, small molecules, DNA, RNA, glycosylations, and multi-chain "
            "complexes in a single forward pass. State-of-the-art accuracy. "
            "Input: FASTA with chain type headers. Output: mmCIF structures."
        ),
        "annotation":  "Chai-1 multi-modal structure prediction. Input: FASTA (chain headers). Output: CIF structures.",
        "tags":        "chai1,chai-1,structure prediction,protein complex,ligand,multi-chain,dna,rna,glycan",
        "domain":      "structural_biology",
        "category":    "Structure Prediction",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/chai1:latest",
        "input_types": ["fasta"],
        "output_types":["cif", "json"],
        "step_count":  2,
        "tools_used":  "Chai-1",
    },
    {
        "name":        "drugclip_virtual_screening",
        "filename":    "drug_discovery/drugclip_virtual_screening/main.nf",
        "description": (
            "Ultra-fast structure-based virtual screening using DrugCLIP (Science 2026). "
            "CLIP-based contrastive learning; 10 million times faster than docking. "
            "Screened 10K proteins x 500M compounds. Input: protein PDB + SMILES file. "
            "Output: ranked compound hits with scores."
        ),
        "annotation":  "DrugCLIP virtual screening. Input: receptor PDB + SMILES. Output: ranked hits CSV.",
        "tags":        "drugclip,virtual screening,drug discovery,docking,CLIP,compound screening,hit finding,SMILES",
        "domain":      "drug_discovery",
        "category":    "Drug Discovery",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/drugclip:latest",
        "input_types": ["pdb", "smi"],
        "output_types":["csv", "json"],
        "step_count":  3,
        "tools_used":  "DrugCLIP",
    },
    {
        "name":        "scfv_antibody_design",
        "filename":    "drug_discovery/scfv_antibody_design/main.nf",
        "description": (
            "AI-driven scFv intrabody design using ProteinMPNN + AlphaFold2 (Science Advances 2026). "
            "Converts conventional antibodies to functional single-chain Fv intrabodies. "
            "73% success rate vs 31% standard methods. "
            "Input: antibody PDB. Output: designed scFv sequences (FASTA) + predicted structures."
        ),
        "annotation":  "scFv antibody design via ProteinMPNN+AF2. Input: antibody PDB. Output: designed FASTA + PDB.",
        "tags":        "scfv,antibody design,intrabody,ProteinMPNN,AlphaFold2,protein design,antibody engineering",
        "domain":      "drug_discovery",
        "category":    "Protein Design",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/scfv-pmpnn:latest",
        "input_types": ["pdb"],
        "output_types":["fasta", "pdb", "json"],
        "step_count":  3,
        "tools_used":  "scFv-pMPNN, AlphaFold2",
    },
    {
        "name":        "syncraft_synthesizability",
        "filename":    "drug_discovery/syncraft_synthesizability/main.nf",
        "description": (
            "LLM-guided molecular synthesizability optimization using SynCraft. "
            "Uses Chain-of-Thought prompting with Gemini-2.5-Pro to predict atom-level edits "
            "(DEL_ATOM, ADD_BOND, DEL_BOND, CHANGE_BOND) that improve synthetic accessibility. "
            "Input: SMILES string or file. Output: optimized SMILES with SA scores."
        ),
        "annotation":  "SynCraft synthesizability optimization (Gemini-2.5-Pro). Input: SMILES. Output: optimized SMILES CSV.",
        "tags":        "syncraft,synthesizability,synthetic accessibility,SA score,molecule optimization,drug design,SMILES",
        "domain":      "drug_discovery",
        "category":    "Drug Discovery",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/syncraft:latest",
        "input_types": ["smiles", "smi"],
        "output_types":["csv", "json"],
        "step_count":  3,
        "tools_used":  "SynCraft, Gemini-2.5-Pro",
    },
    {
        "name":        "protrek_protein_search",
        "filename":    "proteomics/protrek_protein_search/main.nf",
        "description": (
            "Trimodal protein search using ProTrek (Nature Biotechnology 2025). "
            "Unifies sequence, structure, and function through contrastive learning. "
            "Search 5B+ proteins by text description, amino acid sequence, or 3D structure. "
            "Input: text query / FASTA / PDB. Output: ranked protein hits with scores."
        ),
        "annotation":  "ProTrek trimodal protein search. Input: text/sequence/structure. Output: ranked hits JSON+CSV.",
        "tags":        "protrek,protein search,trimodal,sequence search,structure search,function search,proteomics",
        "domain":      "proteomics",
        "category":    "Protein Analysis",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/protrek:latest",
        "input_types": ["text", "fasta", "pdb"],
        "output_types":["json", "csv", "npy"],
        "step_count":  3,
        "tools_used":  "ProTrek",
    },
    {
        "name":        "profam_fitness_prediction",
        "filename":    "proteomics/profam_fitness_prediction/main.nf",
        "description": (
            "Protein variant fitness prediction using ProFAM-1 (251M parameter autoregressive model). "
            "State-of-the-art on ProteinGym benchmark (0.47 substitutions, 0.53 indels Spearman rho). "
            "No multiple sequence alignment required at inference. "
            "Input: FASTA with variants or CSV variant table. Output: fitness scores per variant."
        ),
        "annotation":  "ProFAM-1 fitness scoring. Input: variant FASTA or CSV. Output: fitness scores CSV.",
        "tags":        "profam,fitness prediction,protein engineering,variant effect,ProteinGym,directed evolution",
        "domain":      "proteomics",
        "category":    "Protein Analysis",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/profam:latest",
        "input_types": ["fasta", "csv"],
        "output_types":["csv", "json", "npy"],
        "step_count":  2,
        "tools_used":  "ProFAM-1",
    },
    {
        "name":        "state_perturbation_prediction",
        "filename":    "single_cell/state_perturbation_prediction/main.nf",
        "description": (
            "Virtual cell perturbation prediction using STATE (Arc Institute). "
            "Predicts cellular transcriptional responses to genetic or chemical perturbations "
            "without running experiments. Trained on 270M+ cells including Tahoe-100M. "
            "Input: AnnData h5ad + perturbation name. Output: predicted expression profiles + DEGs."
        ),
        "annotation":  "STATE virtual cell model. Input: h5ad + perturbation. Output: predicted h5ad, DEG CSV.",
        "tags":        "state,virtual cell,perturbation,single cell,transcriptomics,Perturb-seq,genetic perturbation,AnnData",
        "domain":      "single_cell",
        "category":    "Single Cell Analysis",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/state:latest",
        "input_types": ["h5ad"],
        "output_types":["h5ad", "csv", "json"],
        "step_count":  3,
        "tools_used":  "STATE",
    },
]


def _hash(name: str, filename: str) -> str:
    return hashlib.sha256(f"{name}:{filename}".encode()).hexdigest()[:16]


def register(db_path: Path, dry_run: bool = False) -> None:
    conn = sqlite3.connect(db_path)
    cur  = conn.cursor()

    added = 0
    skipped = 0

    for wf in WORKFLOWS:
        wf_hash = _hash(wf["name"], wf["filename"])

        cur.execute("SELECT id FROM workflows WHERE workflow_hash=?", (wf_hash,))
        if cur.fetchone():
            print(f"  [skip] {wf['name']} already registered")
            skipped += 1
            continue

        # Read main.nf for workflow_json
        nf_path = NF_BASE / wf["filename"]
        nf_content = nf_path.read_text() if nf_path.exists() else ""

        if dry_run:
            print(f"  [dry-run] would register: {wf['name']}")
            added += 1
            continue

        cur.execute("""
            INSERT INTO workflows
                (name, filename, description, annotation, tags, domain,
                 workflow_json, step_count, tools_used, source, format,
                 executable, docker_image, category, workflow_hash, indexed_at,
                 input_types, output_types)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            wf["name"],
            wf["filename"],
            wf["description"][:500],
            wf["annotation"],
            wf["tags"],
            wf["domain"],
            nf_content[:8000],          # store first 8K of main.nf
            wf["step_count"],
            wf["tools_used"],
            "nextflow",
            "nextflow",
            1,                           # executable
            wf["docker_image"][:300],
            wf["category"],
            wf_hash,
            datetime.utcnow().isoformat(),
            json.dumps(wf["input_types"]),
            json.dumps(wf["output_types"]),
        ))
        print(f"  [added]  {wf['name']} (id={cur.lastrowid})")
        added += 1

    if not dry_run:
        # Rebuild FTS index
        cur.execute("INSERT INTO workflows_fts(workflows_fts) VALUES('rebuild')")
        conn.commit()
        print(f"\nFTS index rebuilt.")

    conn.close()
    print(f"\nDone: {added} added, {skipped} skipped.")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--db",      default=str(REPO_ROOT / "database" / "galaxy_ai_tools.db"))
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    db_path = Path(args.db)
    if not db_path.exists():
        sys.exit(f"DB not found: {db_path}")

    print(f"Registering 8 AI tool workflows into {db_path}")
    register(db_path, dry_run=args.dry_run)


if __name__ == "__main__":
    main()
