# Biomni Tools Troubleshooting Log

**Date:** 2026-01-19
**Environment:** Docker container `biomate/biomni-tools:latest` (ARM64/aarch64)
**Container:** `exciting_shirley`

## Overview

This document records all troubleshooting efforts to get the Biomni tools working in the Docker environment. The work progressed from 33% to 95% pass rate through systematic debugging.

---

## Session 1: Initial Testing (v1-v5)

### Problem: 92 tools skipped in exhaustive test

**Root Cause:** Missing dependencies, incorrect function signatures, and data format mismatches.

**Solution Process:**
1. Read function docstrings to understand expected parameters
2. Read source code when docstrings were insufficient
3. Created mock data with exact formats required
4. Installed missing dependencies

**Key Findings (v5):**
- `analyze_arsenic_speciation`: Needs `{"species": {"factor": float, "limit": float}}`
- `analyze_ebv_antibody_titers`: Standard curve keys should be `"IgG"` and `"IgM"` only
- `simulate_demographic_history`: Bug in Biomni - adds "pop0" twice for "constant" model

**Result:** 50/55 tools passing (91%)

---

## Session 2: scRNA and Docking Tools (v7)

### Goal: Fix remaining 5 expected failures

The 5 remaining failures were:
1. `genomics.annotate_celltype_scRNA`
2. `genomics.create_harmony_embeddings_scRNA`
3. `genomics.create_scvi_embeddings_scRNA`
4. `pharmacology.docking_autodock_vina`
5. `pharmacology.run_autosite`

---

### Issue 1: scRNA Functions Marked as "Expected Failures"

**Initial Assumption:** These functions need pre-trained models in `data_lake_path`.

**Investigation:**
```bash
# Check function signatures
docker exec exciting_shirley bash -c "grep -A 50 'def create_harmony_embeddings_scRNA' /opt/biomni/src/biomni/tool/genomics.py"
```

**Finding:** `create_harmony_embeddings_scRNA` and `create_scvi_embeddings_scRNA` DON'T need external models! They just need properly formatted AnnData files.

**Required AnnData Structure:**
- `adata.obs['batch']` - batch column for integration
- `adata.obs['celltype']` or `adata.obs['label']` - label column for scVI
- `adata.obsm['X_pca']` - PCA computed (for Harmony)

**Solution - Create Proper Mock AnnData:**
```python
import scanpy as sc
import pandas as pd
import numpy as np

# Create minimal AnnData
np.random.seed(42)
n_cells, n_genes = 100, 200
X = np.random.poisson(lam=3, size=(n_cells, n_genes)).astype(np.float32)

adata = sc.AnnData(X)
adata.obs_names = [f'cell_{i}' for i in range(n_cells)]
adata.var_names = [f'gene_{i}' for i in range(n_genes)]
adata.obs['batch'] = np.random.choice(['batch1', 'batch2'], n_cells)
adata.obs['celltype'] = np.random.choice(['T_cell', 'B_cell', 'Monocyte'], n_cells)
adata.obs['leiden'] = pd.Categorical(np.random.choice(['0', '1', '2'], n_cells))

# Preprocess (REQUIRED for Harmony)
sc.pp.normalize_total(adata)
sc.pp.log1p(adata)
sc.pp.highly_variable_genes(adata, n_top_genes=50)
sc.pp.pca(adata, n_comps=30)  # This creates X_pca

adata.write('test_adata.h5ad')
```

**Test Result:**
```
[PASS] genomics.create_harmony_embeddings_scRNA
[PASS] genomics.create_scvi_embeddings_scRNA
```

**Lesson Learned:** Don't assume "expected failures" are actually failures - verify by testing!

---

### Issue 2: annotate_celltype_scRNA Needs LLM API Key

**Investigation:**
```bash
docker exec exciting_shirley bash -c "grep -A 100 'def annotate_celltype_scRNA' /opt/biomni/src/biomni/tool/genomics.py"
```

**Finding:** Function uses langchain to call Claude LLM for cell type annotation. Also needs:
1. `ANTHROPIC_API_KEY` environment variable
2. `czi_census_datasets_v4.parquet` file in `data_lake_path`

**Solution - Create Mock Parquet:**
```python
import pandas as pd

# Common cell types from CZI cell ontology
cell_types = ['T cell', 'B cell', 'monocyte', 'macrophage', 'dendritic cell', ...]

df = pd.DataFrame({
    'cell_type': ['; '.join(cell_types[:4]), '; '.join(cell_types)],
    'dataset_id': ['ds1', 'ds2']
})
df.to_parquet('/tmp/data_lake/czi_census_datasets_v4.parquet')
```

**Test Result:**
```
ERROR: AuthenticationError: invalid x-api-key
```

**Conclusion:** Function works but needs real API key at runtime. Marked as "needs API key" rather than "broken".

---

### Issue 3: docking_autodock_vina - Complex Dependency Chain

**Investigation:**
```bash
# Check what the function needs
docker exec exciting_shirley bash -c "grep -A 30 'def docking_autodock_vina' /opt/biomni/src/biomni/tool/pharmacology.py"
```

**Finding:** Uses TDC's Oracle with pyscreener:
```python
from tdc import Oracle
oracle = Oracle(name="pyscreener", receptor_pdb_file=..., box_center=..., box_size=...)
```

**Dependency Chain:**
```
docking_autodock_vina
  └── TDC (PyTDC)
       └── pyscreener
            └── pdbfixer
                 └── openmm (conda-only)
            └── openbabel
            └── rdkit
```

**Problem 1: pdbfixer not available via pip**
```bash
pip install pdbfixer
# ERROR: No matching distribution found for pdbfixer
```

**Solution: Install conda and pdbfixer via conda-forge**
```bash
# Install miniconda
cd /tmp && wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-aarch64.sh -O miniconda.sh
bash miniconda.sh -b -p /opt/conda

# Create Python 3.11 environment (matches system Python)
conda create -n biomni311 python=3.11 pdbfixer -y --override-channels -c conda-forge

# Install additional dependencies
conda activate biomni311
conda install -y --override-channels -c conda-forge openbabel rdkit
pip install pyscreener PyTDC --no-deps
```

**Problem 2: TDC requires older rdkit version**
```
pytdc 1.1.15 requires rdkit<2024.3.1,>=2023.9.5, but you have rdkit 2025.9.4
```

**Problem 3: TDC requires tiledb which won't compile on ARM64**
```
subprocess.CalledProcessError: Command '['cmake', ...]' returned non-zero exit status 1
```

**Conclusion:** docking_autodock_vina cannot work on ARM64 due to:
- TDC requires rdkit<2024.3.1 (incompatible with latest conda-forge)
- TDC requires tiledb/tiledbsoma which fail to compile on ARM64

**Workaround:** Would need to build custom conda packages or use x86_64 container.

---

### Issue 4: run_autosite - Missing prepare_receptor Binary

**Investigation:**
```bash
docker exec exciting_shirley bash -c "grep -A 30 'def run_autosite' /opt/biomni/src/biomni/tool/pharmacology.py"
```

**Finding:** Function calls:
```python
subprocess.run(["prepare_receptor", "-r", pdb_file, "-o", pdbqt_file], check=True)
subprocess.run(["autosite", "-r", pdbqt_file, ...], check=True)
```

**Problem:** `prepare_receptor` is from MGLTools/AutoDockTools, which doesn't have ARM64 builds.

**Solution Attempt 1: Use meeko as alternative**
```bash
pip install meeko gemmi prody
```

**Create wrapper script:**
```bash
cat > /usr/local/bin/prepare_receptor << 'SCRIPT'
#!/bin/bash
# Wrapper for meeko's mk_prepare_receptor.py to match MGLTools interface

while [[ $# -gt 0 ]]; do
    case $1 in
        -r) INPUT_PDB="$2"; shift 2 ;;
        -o) OUTPUT_PDBQT="$2"; shift 2 ;;
        *) shift ;;
    esac
done

OUTPUT_DIR=$(dirname "$OUTPUT_PDBQT")
OUTPUT_BASE=$(basename "$OUTPUT_PDBQT" .pdbqt)

cd "$OUTPUT_DIR"
mk_prepare_receptor.py -i "$INPUT_PDB" -o "$OUTPUT_BASE" -p
SCRIPT
chmod +x /usr/local/bin/prepare_receptor
```

**Test Result:**
```bash
prepare_receptor -r /tmp/test_receptor.pdb -o /tmp/test_receptor.pdbqt
# Success! PDBQT file created
```

**Problem 2:** `autosite` binary not available for ARM64
- Part of ADFR suite from Scripps Research
- No ARM64 builds available

**Conclusion:** `prepare_receptor` works via meeko wrapper, but `autosite` is unavailable.

---

## Environment Setup Commands

### Install Conda in Container
```bash
docker exec exciting_shirley bash -c "
cd /tmp
wget -q https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-aarch64.sh -O miniconda.sh
bash miniconda.sh -b -p /opt/conda
rm miniconda.sh
"
```

### Create biomni311 Environment
```bash
docker exec exciting_shirley bash -c "
export PATH=/opt/conda/bin:\$PATH
conda create -n biomni311 python=3.11 pdbfixer openbabel rdkit -y --override-channels -c conda-forge
"
```

### Install prepare_receptor Wrapper
```bash
docker exec exciting_shirley bash -c "
pip install meeko gemmi prody

cat > /usr/local/bin/prepare_receptor << 'SCRIPT'
#!/bin/bash
while [[ \$# -gt 0 ]]; do
    case \$1 in
        -r) INPUT_PDB=\"\$2\"; shift 2 ;;
        -o) OUTPUT_PDBQT=\"\$2\"; shift 2 ;;
        *) shift ;;
    esac
done

if [ -z \"\$INPUT_PDB\" ] || [ -z \"\$OUTPUT_PDBQT\" ]; then
    echo \"Usage: prepare_receptor -r input.pdb -o output.pdbqt\"
    exit 1
fi

OUTPUT_DIR=\$(dirname \"\$OUTPUT_PDBQT\")
OUTPUT_BASE=\$(basename \"\$OUTPUT_PDBQT\" .pdbqt)

cd \"\$OUTPUT_DIR\"
mk_prepare_receptor.py -i \"\$INPUT_PDB\" -o \"\$OUTPUT_BASE\" -p
SCRIPT

chmod +x /usr/local/bin/prepare_receptor
"
```

### Create CZI Census Mock Parquet
```bash
docker exec exciting_shirley python << 'PYEOF'
import pandas as pd
import os

DATA_LAKE = '/tmp/data_lake'
os.makedirs(DATA_LAKE, exist_ok=True)

cell_types = [
    'T cell', 'B cell', 'monocyte', 'macrophage', 'dendritic cell',
    'natural killer cell', 'neutrophil', 'eosinophil', 'basophil',
    'fibroblast', 'epithelial cell', 'endothelial cell', 'neuron'
]

df = pd.DataFrame({
    'cell_type': ['; '.join(cell_types[:4]), '; '.join(cell_types)],
    'dataset_id': ['ds1', 'ds2']
})
df.to_parquet(f'{DATA_LAKE}/czi_census_datasets_v4.parquet')
print(f'Created {DATA_LAKE}/czi_census_datasets_v4.parquet')
PYEOF
```

---

## Final Results Summary

| Version | Pass Rate | Key Changes |
|---------|-----------|-------------|
| v1 | 33% | Initial test with basic mock data |
| v2 | 47% | Fixed function signatures |
| v3 | 62% | Correct signatures + dependencies |
| v4 | 85% | Exact docstring data formats |
| v5 | 91% | Source code analysis + bug workarounds |
| v7 | 95% | scRNA functions now work |

### Final Status: 52/55 Tools Working (95%)

| Category | Status |
|----------|--------|
| Literature | 2/2 ✅ |
| Genomics | 6/7 (annotate_celltype needs API key) |
| Biochemistry | 1/1 ✅ |
| Microbiology | 6/6 ✅ |
| Biophysics | 1/1 ✅ |
| Pharmacology | 9/11 (2 docking tools have ARM64 issues) |
| Synthetic Biology | 2/2 ✅ |
| Systems Biology | 4/4 ✅ |
| Immunology | 4/4 ✅ |
| Cell Biology | 1/1 ✅ |
| Cancer Biology | 2/2 ✅ |
| Physiology | 3/3 ✅ |
| Pathology | 6/6 ✅ |
| Bioengineering | 2/2 ✅ |
| Genetics | 4/4 ✅ |
| Lab Automation | 1/1 ✅ |

### Remaining 3 Failures

| Tool | Issue | Potential Fix |
|------|-------|---------------|
| `annotate_celltype_scRNA` | Needs ANTHROPIC_API_KEY | Set env var at runtime |
| `docking_autodock_vina` | TDC+tiledb ARM64 incompatible | Use x86_64 container |
| `run_autosite` | autosite binary unavailable | Use x86_64 container |

---

## Key Lessons Learned

1. **Don't trust "expected failure" labels** - Always verify by actually testing
2. **Read source code, not just docstrings** - Implementations may differ from docs
3. **ARM64 has limited support** - Many bioinformatics tools don't have ARM64 builds
4. **Conda vs pip** - Some packages (pdbfixer, openmm) only available via conda
5. **Version conflicts** - PyTDC requires specific older versions that conflict with current packages
6. **Mock data matters** - Correct data structure is crucial (e.g., AnnData needs X_pca for Harmony)

---

## Files Created/Modified

| File | Purpose |
|------|---------|
| `Biomni/tests/test_skipped_tools_v5.py` | Test with 91% pass rate |
| `Biomni/tests/test_skipped_tools_v7.py` | Test with scRNA working |
| `docs/BIOMNI_TOOL_REQUIREMENTS_KNOWLEDGE.md` | Function signatures and formats |
| `docs/BIOMNI_TROUBLESHOOTING_LOG.md` | This troubleshooting document |
| `20260119_BIOMNI_SKIPPED_TOOLS_TEST_SUMMARY.md` | Summary of test results |
| `/usr/local/bin/prepare_receptor` (in container) | Meeko wrapper for MGLTools |
| `/tmp/data_lake/czi_census_datasets_v4.parquet` (in container) | Mock CZI census data |
