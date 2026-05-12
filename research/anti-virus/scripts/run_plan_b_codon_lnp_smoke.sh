#!/usr/bin/env bash
# Plan B (mRNA / LNP / codon): print demo `nextflow run` and `curl` examples for the five
# workflows listed in research/anti-virus/ANDV_VACCINE_PLAN_B_mRNA_LNP_IMPLEMENTATION.md
# (ids 10813, 10721, 12819, 12869, 12867). Does not execute Nextflow or curl.
#
# API auth: set GALAXY_API_KEY in your environment (never commit keys).
# Usage: ./research/anti-virus/scripts/run_plan_b_codon_lnp_smoke.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
BIOMNI="${ROOT}/backend/biomni_workflows"
: "${BIOMATE_API_URL:=http://127.0.0.1:8081}"

echo "Plan B smoke — printed examples only (registry ids 10813, 10721, 12819, 12869, 12867)."
echo "Repo: ${ROOT}"
echo "Local Nextflow cwd: ${BIOMNI}"
echo "API base: ${BIOMATE_API_URL}"
echo

echo "========== 10813 — codon / heterologous expression =========="
echo "# Local nextflow (GFP-coding demo fragment; same defaults as workflow main.nf):"
echo "cd ${BIOMNI}/nextflow_nfcore/subworkflows/synthetic_biology/optimize_codons_for_heterologous_expression"
echo "nextflow run main.nf \\"
echo "  --outdir ./results_plan_b_demo \\"
echo "  --target_sequence 'ATGAGTAAAGGAGAAGAACTTTTCACTGGAGTTGTCCCAATTCTTGTTGAATTAGATGGTGATGTTAATGGGCACAAATTTTCTGTCAGTGGAGAGGGTGAAGGTGATGCAACATACGGAAAACTTACCCTTAAATTTATTTGCACTACTGGAAAACTACCTGTTCCATGG' \\"
echo "  --host_codon_usage '{\"TTT\":0.58,\"TTC\":0.42,\"ATG\":1.00}'"
echo

echo "# curl — POST /api/nextflow/execute (id 10813 path; set GALAXY_API_KEY):"
cat <<EOF
curl -sS -X POST "${BIOMATE_API_URL%/}/api/nextflow/execute" \\
  -H "Content-Type: application/json" \\
  -H "X-API-Key: \${GALAXY_API_KEY}" \\
  -d '{
  "nextflow_path": "nextflow_nfcore/subworkflows/synthetic_biology/optimize_codons_for_heterologous_expression/main.nf",
  "workflow_domain": "synthetic_biology",
  "user_id": "plan_b_demo",
  "profile": "aws",
  "compute_config": {"executor": "awsbatch", "s3_bucket": "biomate-nextflow-work"},
  "parameters": {
    "outdir": "s3://biomate-nextflow-work/nextflow/outputs/plan_b_demo/codon_smoke/",
    "target_sequence": "ATGAGTAAAGGAGAAGAACTTTTCACTGGAGTTGTCCCAATTCTTGTTGAATTAGATGGTGATGTTAATGGGCACAAATTTTCTGTCAGTGGAGAGGGTGAAGGTGATGCAACATACGGAAAACTTACCCTTAAATTTATTTGCACTACTGGAAAACTACCTGTTCCATGG",
    "host_codon_usage": "{\"TTT\":0.58,\"TTC\":0.42,\"ATG\":1.00}"
  }
}'
EOF

echo
echo "========== 10721 — RNA secondary structure (ViennaRNA) =========="
echo "cd ${BIOMNI}/nextflow_nfcore/subworkflows/microbiology/predict_rna_secondary_structure"
echo "nextflow run main.nf --outdir ./results_plan_b_demo --rna_sequence 'GGGCUAUAGCUCAGCUGGGAGAGCGCUUGCAUGGCAUGCAAGAGGUCAGCGGUUCGAUCCCGCUUAGCUCCACCA' --output_prefix plan_b_demo"
echo
echo "# curl (id 10721 path):"
cat <<EOF
curl -sS -X POST "${BIOMATE_API_URL%/}/api/nextflow/execute" \\
  -H "Content-Type: application/json" \\
  -H "X-API-Key: \${GALAXY_API_KEY}" \\
  -d '{
  "nextflow_path": "nextflow_nfcore/subworkflows/microbiology/predict_rna_secondary_structure/main.nf",
  "workflow_domain": "microbiology",
  "user_id": "plan_b_demo",
  "profile": "aws",
  "compute_config": {"executor": "awsbatch", "s3_bucket": "biomate-nextflow-work"},
  "parameters": {
    "outdir": "s3://biomate-nextflow-work/nextflow/outputs/plan_b_demo/rna2d_smoke/",
    "rna_sequence": "GGGCUAUAGCUCAGCUGGGAGAGCGCUUGCAUGGCAUGCAAGAGGUCAGCGGUUCGAUCCCGCUUAGCUCCACCA",
    "output_prefix": "plan_b_demo"
  }
}'
EOF

echo
echo "========== 12819 — P0 mRNA validation (public GenBank demo) =========="
echo "cd ${BIOMNI}/nextflow_nfcore/subworkflows/drug_discovery/p0_mrna_validation"
echo "nextflow run main.nf --outdir ./results_plan_b_demo --genbank_id MN908947.3 --orf_start 21563 --orf_end 25384 --cai_threshold 0.90 --mfe_threshold -150.0"
echo
echo "# curl (id 12819 path):"
cat <<EOF
curl -sS -X POST "${BIOMATE_API_URL%/}/api/nextflow/execute" \\
  -H "Content-Type: application/json" \\
  -H "X-API-Key: \${GALAXY_API_KEY}" \\
  -d '{
  "nextflow_path": "nextflow_nfcore/subworkflows/drug_discovery/p0_mrna_validation/main.nf",
  "workflow_domain": "drug_discovery",
  "user_id": "plan_b_demo",
  "profile": "aws",
  "compute_config": {"executor": "awsbatch", "s3_bucket": "biomate-nextflow-work"},
  "parameters": {
    "outdir": "s3://biomate-nextflow-work/nextflow/outputs/plan_b_demo/p0_mrna_smoke/",
    "genbank_id": "MN908947.3",
    "orf_start": "21563",
    "orf_end": "25384",
    "cai_threshold": "0.90",
    "mfe_threshold": "-150.0"
  }
}'
EOF

echo
echo "========== 12869 — LNP formulation optimization =========="
echo "cd ${BIOMNI}/nextflow_nfcore/subworkflows/drug_discovery/lnp_formulation_optimization"
echo "nextflow run main.nf --outdir ./results_plan_b_demo --cargo_type mRNA --target_tissue liver --run_ratio_sweep false"
echo
echo "# curl (id 12869 path; uses workflow defaults for lipid SMILES if omitted server-side — pass explicitly for clarity):"
cat <<EOF
curl -sS -X POST "${BIOMATE_API_URL%/}/api/nextflow/execute" \\
  -H "Content-Type: application/json" \\
  -H "X-API-Key: \${GALAXY_API_KEY}" \\
  -d '{
  "nextflow_path": "nextflow_nfcore/subworkflows/drug_discovery/lnp_formulation_optimization/main.nf",
  "workflow_domain": "drug_discovery",
  "user_id": "plan_b_demo",
  "profile": "aws",
  "compute_config": {"executor": "awsbatch", "s3_bucket": "biomate-nextflow-work"},
  "parameters": {
    "outdir": "s3://biomate-nextflow-work/nextflow/outputs/plan_b_demo/lnp_smoke/",
    "cargo_type": "mRNA",
    "target_tissue": "liver",
    "run_ratio_sweep": "false"
  }
}'
EOF

echo
echo "========== 12867 — nanoparticle PK / biodistribution =========="
echo "cd ${BIOMNI}/nextflow_nfcore/subworkflows/pharmacology/nanoparticle_pk_biodistribution"
echo "nextflow run main.nf --outdir ./results_plan_b_demo --particle_diameter_nm 100 --surface_chemistry PEG --PEG_density_chains_nm2 0.15 --dose_mg_kg 5 --simulation_hours 24"
echo
echo "# curl (id 12867 path):"
cat <<EOF
curl -sS -X POST "${BIOMATE_API_URL%/}/api/nextflow/execute" \\
  -H "Content-Type: application/json" \\
  -H "X-API-Key: \${GALAXY_API_KEY}" \\
  -d '{
  "nextflow_path": "nextflow_nfcore/subworkflows/pharmacology/nanoparticle_pk_biodistribution/main.nf",
  "workflow_domain": "pharmacology",
  "user_id": "plan_b_demo",
  "profile": "aws",
  "compute_config": {"executor": "awsbatch", "s3_bucket": "biomate-nextflow-work"},
  "parameters": {
    "outdir": "s3://biomate-nextflow-work/nextflow/outputs/plan_b_demo/np_pk_smoke/",
    "particle_diameter_nm": "100",
    "surface_chemistry": "PEG",
    "PEG_density_chains_nm2": "0.15",
    "dose_mg_kg": "5",
    "simulation_hours": "24"
  }
}'
EOF

echo
echo "Done (nothing executed)."
