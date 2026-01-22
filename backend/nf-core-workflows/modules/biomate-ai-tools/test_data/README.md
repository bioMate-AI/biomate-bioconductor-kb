# Test Data for Biomate AI Tools

This directory contains test data for validating the Nextflow modules.

## Files

| File | Format | Used By | Description |
|------|--------|---------|-------------|
| `test.fasta` | FASTA | esmfold, alphafold, boltz, chai1, protrek, profam | Hemoglobin protein sequence |
| `test_dna.fasta` | FASTA | chai1 | DNA sequence for multi-modal testing |
| `test_compounds.smi` | SMILES | drugclip | Compound library (8 common drugs) |
| `test_ligand.sdf` | SDF | boltz, chai1 | Aspirin 3D structure for docking |
| `test_smiles.txt` | SMILES | syncraft | Single molecule for retrosynthesis |
| `test_antibody.pdb` | PDB | scfv-pmpnn | Minimal scFv antibody structure |
| `esmfold_result.pdb` | PDB | (reference) | Example ESMFold output |

## Missing Test Data

### STATE (scRNA-seq)
STATE requires h5ad format single-cell data which is too large for this repository.

Download test data:
```bash
# Download PBMC 3k dataset (~50 MB)
wget https://cf.10xgenomics.com/samples/cell-exp/1.1.0/pbmc3k/pbmc3k_filtered_gene_bc_matrices.tar.gz
# Or use scanpy's built-in datasets
python -c "import scanpy as sc; adata = sc.datasets.pbmc3k(); adata.write('test_pbmc3k.h5ad')"
```

## Running Tests

### Quick test (API-based tools, no GPU needed)
```bash
# ESMFold - uses free API
nextflow run ../esmfold/main.nf --input test.fasta --outdir results/

# SynCraft - uses Gemini API (needs GEMINI_API_KEY)
export GEMINI_API_KEY=your_key
nextflow run ../syncraft/main.nf --smiles "CC(=O)Oc1ccccc1C(=O)O" --outdir results/
```

### GPU tests (requires NVIDIA GPU)
```bash
# DrugCLIP virtual screening
nextflow run ../drugclip/main.nf \
    --target test.fasta \
    --compounds test_compounds.smi \
    --outdir results/

# Boltz structure prediction with ligand
nextflow run ../boltz/main.nf \
    --input test.fasta \
    --ligand test_ligand.sdf \
    --outdir results/

# Chai-1 multi-modal prediction
nextflow run ../chai1/main.nf \
    --input test.fasta \
    --outdir results/

# ProTrek protein search
nextflow run ../protrek/main.nf \
    --query test.fasta \
    --mode sequence \
    --outdir results/

# ProFam fitness prediction
nextflow run ../profam/main.nf \
    --input test.fasta \
    --outdir results/

# scFv-pMPNN antibody design
nextflow run ../scfv-pmpnn/main.nf \
    --input test_antibody.pdb \
    --outdir results/
```

### STATE (requires h5ad data + GPU)
```bash
# First download test data (see above)
nextflow run ../state/main.nf \
    --input test_pbmc3k.h5ad \
    --perturbation "TP53 knockout" \
    --outdir results/
```

## Expected Outputs

| Tool | Output Files |
|------|--------------|
| esmfold | `*.pdb` (predicted structure) |
| alphafold | `*.pdb` or AlphaFold DB JSON |
| boltz | `*.pdb`, `*_affinity.json` |
| chai1 | `*.pdb`, confidence scores |
| drugclip | `scores.csv`, `top_hits.csv` |
| protrek | `results.json` (similar proteins) |
| profam | `fitness_scores.csv` |
| state | `predictions.h5ad` |
| scfv-pmpnn | `designed_sequences.fasta`, `*.pdb` |
| syncraft | `synthesis_route.json` |
