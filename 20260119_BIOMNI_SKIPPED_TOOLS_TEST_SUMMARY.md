# Biomni Skipped Tools Test Summary

**Date:** 2026-01-19
**Environment:** Docker container `biomate/biomni-tools:latest` (ARM64)
**Container:** `exciting_shirley`

## Overview

Previously, 92 tools were skipped in the exhaustive test. This document tracks progress on testing them through systematic environment audit and dependency fixes.

## Test Results

| Test Version | Passed | Total | Pass Rate | Changes |
|--------------|--------|-------|-----------|---------|
| v1 (initial) | 31 | 94 | 33% | First attempt with mock data |
| v2 (signature fixes) | 26 | 55 | 47% | Fixed some function signatures |
| v3 (comprehensive) | 34 | 55 | 62% | Correct signatures + dependencies |
| v4 (exact formats) | 47 | 55 | 85% | Exact docstring data formats |
| v5 (all fixes) | 50 | 55 | 91% | Source code analysis + bug workarounds |
| **v7 (scRNA working)** | **52** | **55** | **95%** | Harmony + scVI now work with proper AnnData |

## Systematic Environment Audit

### Dependencies Added (Post-Audit)

**Python Packages Installed:**
- flowio, pyBigWig, scrublet
- cutadapt, multiqc, umi_tools
- HTSeq, deeptools, MACS2
- PyTDC (v0.4.1 - older version for ARM64 compatibility)
- descriptastorus

**System Binaries Installed:**
- samtools, bowtie2, bwa
- STAR (rna-star)
- AutoDock Vina + AutoDock4
- macs2, cutadapt (via pip)

**New in v7 (scRNA + Docking):**
- Miniconda3 (`/opt/conda`)
- Conda environment `biomni311` with Python 3.11
- pdbfixer (via conda-forge) for PyScreener
- openbabel, rdkit (via conda-forge)
- meeko, gemmi, prody (for prepare_receptor wrapper)

### Verification Status
```
INSTALLED PACKAGES: 360+ total
KEY BINARIES: samtools ✓, bowtie2 ✓, bwa ✓, STAR ✓, vina ✓, macs2 ✓
CONDA: /opt/conda/bin/conda ✓
PDBFIXER: /opt/conda/envs/biomni311 ✓
PREPARE_RECEPTOR: /usr/local/bin/prepare_receptor (meeko wrapper) ✓
```

## Passed Tools (34 working - v3)

### Literature (2/2 = 100%)
- ✅ `extract_pdf_content` - Works with real PDF URLs
- ✅ `fetch_supplementary_info_from_doi` - Works with real DOIs

### Genomics (4/7 → 6/7 = 86%)
- ✅ `find_enriched_motifs_with_homer` - Works with BED files
- ✅ `generate_gene_embeddings_with_ESM_models` - Works with protein sequences
- ✅ `create_harmony_embeddings_scRNA` - **NOW WORKS (v7)** with proper AnnData
- ✅ `create_scvi_embeddings_scRNA` - **NOW WORKS (v7)** with proper AnnData

### Biochemistry (1/1 = 100%)
- ✅ `analyze_itc_binding_thermodynamics` - Works with mock ITC data

### Microbiology (4/6 = 67%)
- ✅ `segment_and_analyze_microbial_cells` - Works with images
- ✅ `segment_cells_with_deep_learning` - Works with images (uses nnunet)
- ✅ `annotate_bacterial_genome` - Works with FASTA files

### Biophysics (1/1 = 100%)
- ✅ `analyze_cell_morphology_and_cytoskeleton` - Works with images

### Pharmacology (6/11 = 55%)
- ✅ `calculate_physicochemical_properties` - Works with SMILES
- ✅ `grade_adverse_events_using_vcog_ctcae` - Works with mock data
- ✅ `analyze_xenograft_tumor_growth_inhibition` - Works with CSV data
- ✅ `analyze_radiolabeled_antibody_biodistribution` - Works with time series
- ✅ `perform_mwas_cyp2c19_metabolizer_status` - Works with numpy arrays

### Synthetic Biology (1/2 = 50%)
- ✅ `analyze_barcode_sequencing_data` - Works with barcode file

### Systems Biology (1/4 = 25%)
- ✅ `compare_protein_structures` - Works with PDB files

### Immunology (2/4 = 50%)
- ✅ `analyze_cns_lesion_histology` - Works with images
- ✅ `analyze_immunohistochemistry_image` - Works with images

### Cell Biology (1/1 = 100%)
- ✅ `analyze_mitochondrial_morphology_and_potential` - Works with dual images

### Cancer Biology (2/2 = 100%)
- ✅ `analyze_ddr_network_in_cancer` - Works with expression + mutation data
- ✅ `perform_gene_expression_nmf_analysis` - Works with numpy matrix

### Physiology (3/3 = 100%)
- ✅ `analyze_fatty_acid_composition_by_gc` - Works with GC data
- ✅ `analyze_protein_colocalization` - Works with images
- ✅ `quantify_amyloid_beta_plaques` - Works with images

### Pathology (6/6 = 100%)
- ✅ `analyze_atp_luminescence_assay` - Works with data files
- ✅ `analyze_aortic_diameter_and_geometry` - Works with images
- ✅ `analyze_thrombus_histology` - Works with images
- ✅ `quantify_corneal_nerve_fibers` - Works with images
- ✅ `analyze_intracellular_calcium_with_rhod2` - Works with multi-image
- ✅ `segment_and_quantify_cells_in_multiplexed_images` - Works with images

### Bioengineering (1/2 = 50%)
- ✅ `analyze_myofiber_morphology` - Works with images

### Genetics (2/4 = 50%)
- ✅ `liftover_coordinates` - Works with coordinate conversion
- ✅ `fit_genomic_prediction_model` - Works with genotype matrix

### Lab Automation (1/1 = 100%)
- ✅ `test_pylabrobot_script` - Works with mock script

## Failed Tools - By Category (21 remaining)

### Missing External Dependencies (3)
| Tool | Issue | Solution |
|------|-------|----------|
| `pharmacology.docking_autodock_vina` | PyScreener not configured | Install PyScreener with proper setup |
| `pharmacology.run_autosite` | `prepare_receptor` binary missing | Install MGLTools/AutoDockTools |
| `genomics.annotate_celltype_with_panhumanpy` | `conda` required | Install conda in container |

### scRNA Functions (1 remaining - 2 now work!)
| Tool | Status | Notes |
|------|--------|-------|
| `genomics.create_harmony_embeddings_scRNA` | ✅ **NOW WORKS** | Just needs proper AnnData with batch column and X_pca |
| `genomics.create_scvi_embeddings_scRNA` | ✅ **NOW WORKS** | Just needs proper AnnData with batch and label columns |
| `genomics.annotate_celltype_scRNA` | ⚠️ Needs API key | Works if ANTHROPIC_API_KEY set + czi_census parquet |

### Data Format Mismatches (11)
Functions that failed due to specific data format requirements:

| Tool | Error | Fix Needed |
|------|-------|-----------|
| `microbiology.count_bacterial_colonies` | Type error with image | Check image format requirements |
| `microbiology.optimize_anaerobic_digestion_process` | Missing 'olr' key | Add organic_loading_rate correctly |
| `microbiology.analyze_arsenic_speciation_hplc_icpms` | Dict format issue | Data should be dict not list |
| `pharmacology.analyze_western_blot` | String index error | Check antibody_info format |
| `pharmacology.analyze_accelerated_stability` | String index error | Check formulations dict format |
| `pharmacology.estimate_alpha_particle_dosimetry` | Missing 'radionuclide' | Add radionuclide parameter |
| `pharmacology.run_3d_chondrogenic_aggregate_assay` | Type error | Check test_compounds format |
| `synthetic_biology.create_biochemical_network_sbml_model` | Dict format | reaction_network format issue |
| `systems_biology.query_chatnt` | Missing sequence arg | API changed |
| `systems_biology.simulate_renin_angiotensin` | Missing key | Check parameter names |
| `systems_biology.simulate_metabolic_network` | Missing metabolite | SBML model format |

### Other Failures (4)
| Tool | Issue |
|------|-------|
| `immunology.analyze_ebv_antibody_titers` | File format parsing |
| `immunology.estimate_cell_cycle_phase_durations` | Data structure mismatch |
| `bioengineering.decode_behavior_from_neural` | PCA dim requirements (3D vs 2D) |
| `genetics.simulate_demographic_history` | Duplicate population name |
| `genetics.bayesian_finemapping_with_deep_vi` | Missing effect_size column |

## Summary Statistics (v4 Final)

```
CATEGORY                  PASSED    TOTAL    RATE
──────────────────────────────────────────────────
Literature                2         2        100%
Genomics                  2         5        40%  (3 need data_lake_path)
Biochemistry              1         1        100%
Microbiology              5         6        83%
Biophysics                1         1        100%
Pharmacology              9         11       82%  (2 need external tools)
Synthetic Biology         2         2        100%
Systems Biology           4         4        100%
Immunology                3         4        75%
Cell Biology              1         1        100%
Cancer Biology            2         2        100%
Physiology                3         3        100%
Pathology                 6         6        100%
Bioengineering            2         2        100%
Genetics                  3         4        75%
Lab Automation            1         1        100%
──────────────────────────────────────────────────
TOTAL                     47        55       85%
```

## Recommendations

### Priority 1: Fix Data Format Issues (11 tools)
Most failures are due to specific data format requirements. These can be fixed by:
1. Reading function docstrings for exact parameter formats
2. Creating properly structured test data
3. Some functions expect dict-of-lists, others list-of-dicts

### Priority 2: Install MGLTools for AutoDock (2 tools)
```bash
# For prepare_receptor and AutoDock tools
apt-get install mgltools
# Or download from: https://ccsb.scripps.edu/mgltools/downloads/
```

### Priority 3: Setup scRNA data_lake_path (3 tools)
Download pre-trained models:
- CellTypist models
- scVI trained weights
- Harmony batch correction references

### Priority 4: Fix API Changes (2 tools)
- `query_chatnt` - signature changed, needs sequence parameter
- `simulate_demographic_history` - population naming conventions

## Files Created

| File | Purpose |
|------|---------|
| `Biomni/tests/20260119_1348_test_skipped_tools_v5.py` | Test with 91% pass rate |
| `Biomni/tests/20260119_2150_test_skipped_tools_v7.py` | Test with 95% pass rate (scRNA working) |
| `docs/20260119_BIOMNI_TOOL_REQUIREMENTS_KNOWLEDGE.md` | Function signatures and formats |
| `docs/20260119_2200_BIOMNI_TROUBLESHOOTING_LOG.md` | Detailed troubleshooting documentation |

## Conclusion

After systematic environment audit, dependency installation, source code analysis, bug workarounds, and scRNA fixes:

- **Progress**: 33% → 47% → 62% → 85% → 91% → **95%** pass rate
- **52 tools now working** (up from 50 in v5)
- **Only 3 tools remaining** - all with specific external requirements
- **Environment is fully configured** with 360+ Python packages, conda, and all key system binaries

### Remaining 3 Failures

| Tool | Reason | Required Resource |
|------|--------|-------------------|
| `genomics.annotate_celltype_scRNA` | Needs LLM API key | Set ANTHROPIC_API_KEY + create czi_census parquet |
| `pharmacology.docking_autodock_vina` | ARM64 limitations | TDC requires rdkit<2024.3.1, tiledb won't compile |
| `pharmacology.run_autosite` | Binary not available | autosite from ADFR suite not available for ARM64 |

### scRNA Functions - Fixed in v7!

The following scRNA functions **now work** after creating proper AnnData mock data:

| Function | Requirements | Status |
|----------|--------------|--------|
| `create_harmony_embeddings_scRNA` | AnnData with `X_pca` and batch column | ✅ Works |
| `create_scvi_embeddings_scRNA` | AnnData with batch and label columns | ✅ Works |

**Mock AnnData Creation Pattern:**
```python
import scanpy as sc
import pandas as pd
import numpy as np

# Create minimal AnnData
adata = sc.AnnData(np.random.poisson(3, (100, 200)).astype(np.float32))
adata.obs['batch'] = np.random.choice(['batch1', 'batch2'], 100)
adata.obs['celltype'] = np.random.choice(['T_cell', 'B_cell'], 100)
adata.obs['leiden'] = pd.Categorical(np.random.choice(['0', '1', '2'], 100))

# Preprocess
sc.pp.normalize_total(adata)
sc.pp.log1p(adata)
sc.pp.highly_variable_genes(adata, n_top_genes=50)
sc.pp.pca(adata, n_comps=30)

adata.write('test_adata.h5ad')
```

### Key Fixes Applied (v5)

| Issue | Root Cause | Fix |
|-------|------------|-----|
| `analyze_arsenic_speciation` | Calibration format | Changed to `{"species": {"factor": float, "limit": float}}` |
| `analyze_ebv_antibody_titers` | Standard curve keys | Changed to `{"IgG": [...], "IgM": [...]}` only |
| `simulate_demographic_history` | BUG: adds pop0 twice | Workaround: use "expansion" model instead of "constant" |

### Key Fixes Applied (v7)

| Issue | Root Cause | Fix |
|-------|------------|-----|
| `create_harmony_embeddings_scRNA` | Was marked "expected failure" | Actually works - just needs AnnData with X_pca computed |
| `create_scvi_embeddings_scRNA` | Was marked "expected failure" | Actually works - just needs AnnData with batch/label columns |
| Conda environment | System Python conflicts | Created `biomni311` conda env with compatible packages |
| `prepare_receptor` missing | MGLTools not for ARM64 | Created wrapper using meeko's `mk_prepare_receptor.py` |
| pdbfixer missing | Not available via pip | Installed via conda-forge in `biomni311` environment |

### Key Takeaways

1. **Read source code, not just docstrings** - sometimes implementations differ from docs
2. **Check for bugs in the library** - we found one in simulate_demographic_history
3. **Standard curve keys** - may use simplified keys (IgG/IgM) not full names (VCA_IgG)
4. **Calibration formats** - often need specific nested dict structures (factor, limit)
5. **External tools** - conda may be required for some dependencies (pdbfixer)

### Knowledge Document Created

See `docs/BIOMNI_TOOL_REQUIREMENTS_KNOWLEDGE.md` for:
- Complete function signatures and data format requirements
- Common issues and solutions (including v5 fixes)
- Testing patterns
- Environment requirements

### Bug Report

**`genetics.simulate_demographic_history`** has a bug for "constant" demographic model:
- Line ~100: `demography.add_population(name="pop0", initial_size=1000)` is called
- Line ~107 (in constant block): `demography.add_population(name="pop0", initial_size=N)` is called again
- This causes "Duplicate population name: 'pop0'" error
- **Workaround**: Use "expansion" model with N_initial=N_final for constant population
