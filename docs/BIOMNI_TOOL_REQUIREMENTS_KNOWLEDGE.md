# Biomni Tool Requirements Knowledge Base

**Created:** 2026-01-19
**Updated:** 2026-01-19 (v7)
**Purpose:** Reference for BioMate when calling Biomni tools with correct parameters
**Test Pass Rate:** 95% (52/55 previously skipped tools)

---

## Table of Contents
1. [Environment Requirements](#environment-requirements)
2. [Function Categories and Data Formats](#function-categories-and-data-formats)
3. [Common Issues and Solutions](#common-issues-and-solutions)
4. [Tool-Specific Requirements](#tool-specific-requirements)
5. [Testing Patterns](#testing-patterns)

---

## Environment Requirements

### Python Packages (Must Have)
```
# Core bioinformatics
numpy, scipy, pandas, biopython, anndata, scanpy

# Image processing
scikit-image, opencv-python-headless, Pillow, nibabel, SimpleITK

# Chemistry
rdkit, pubchempy

# Flow cytometry
flowio, FlowKit

# Literature
arxiv, scholarly, PyPDF2, pymed

# Deep learning
torch, transformers, accelerate

# Genomics tools
pysam, pybedtools, cooler, pyBigWig

# scRNA
scvi-tools, cellpose, harmony-pytorch, scrublet

# QC tools
cutadapt, multiqc, HTSeq, deeptools, MACS2

# Therapeutics
PyTDC (use v0.4.1 for ARM64 compatibility)
```

### System Binaries (Must Have)
```bash
samtools, bowtie2, bwa, STAR, macs2
autodock-vina, autodock4
```

### Optional Dependencies
```
# For docking
MGLTools (provides prepare_receptor)
PyScreener

# For conda-based tools
miniconda/anaconda
```

---

## Function Categories and Data Formats

### 1. MICROBIOLOGY

#### `count_bacterial_colonies`
```python
# Signature
count_bacterial_colonies(image_path, dilution_factor=1, plate_area_cm2=65.0, output_dir='./output')

# Usage
result = microbiology.count_bacterial_colonies(
    image_path="/path/to/plate_image.png",
    dilution_factor=1,
    plate_area_cm2=65.0,
    output_dir="./output"
)
```

#### `optimize_anaerobic_digestion_process`
```python
# Signature
optimize_anaerobic_digestion_process(waste_characteristics, operational_parameters,
                                     target_output='methane_yield', optimization_method='rsm')

# CRITICAL: operational_parameters values must be TUPLES (min, max), not single values
waste_characteristics = {
    "total_solids": 15.0,      # float (%)
    "volatile_solids": 75.0,   # float (%)
    "cod": 50000.0             # float (mg/L)
}

operational_parameters = {
    "hrt": (10, 30),           # TUPLE: (min, max) days
    "olr": (1.0, 4.0),         # TUPLE: (min, max) kg VS/(m³·d)
    "if_ratio": (0.5, 2.0),    # TUPLE: (min, max)
    "temperature": (30, 45),   # TUPLE: (min, max) °C
    "ph": (6.5, 8.0)           # TUPLE: (min, max)
}
```

#### `analyze_arsenic_speciation_hplc_icpms`
```python
# Signature
analyze_arsenic_speciation_hplc_icpms(sample_data, sample_name='Unknown Sample', calibration_data=None)

# sample_data format: dict with sample IDs as keys, values are dicts with retention_time: intensity
sample_data = {
    "sample_001": {2.5: 15000, 4.2: 8500, 6.1: 3200},
    "sample_002": {2.5: 12000, 4.2: 9200, 6.1: 2800}
}
```

---

### 2. PHARMACOLOGY

#### `analyze_western_blot`
```python
# Signature
analyze_western_blot(blot_image_path, target_bands, loading_control_band, antibody_info, output_dir='./results')

# target_bands: LIST of dicts with 'name' and 'roi' [x, y, width, height]
target_bands = [
    {"name": "p53", "roi": [100, 50, 50, 30]},
    {"name": "Bcl-2", "roi": [100, 100, 50, 30]}
]

# loading_control_band: dict with 'name' and 'roi'
loading_control_band = {"name": "GAPDH", "roi": [100, 200, 50, 30]}

# antibody_info: dict with 'primary' and 'secondary' info
antibody_info = {
    "primary": {"name": "anti-p53", "dilution": "1:1000", "source": "mouse"},
    "secondary": {"name": "anti-mouse HRP", "dilution": "1:5000"}
}
```

#### `analyze_accelerated_stability_of_pharmaceutical_formulations`
```python
# Signature
analyze_accelerated_stability_of_pharmaceutical_formulations(formulations, storage_conditions, time_points)

# CRITICAL: formulations is LIST of dicts, NOT a single dict
formulations = [
    {
        "name": "Formulation A",
        "active_ingredient": "Aspirin",
        "concentration": 100.0,  # mg/mL
        "excipients": ["lactose", "starch", "magnesium stearate"]
    }
]

# storage_conditions is LIST of dicts
storage_conditions = [
    {"temperature": 25.0, "humidity": 60.0, "description": "Room Temperature"},
    {"temperature": 40.0, "humidity": 75.0, "description": "Accelerated"}
]

# time_points is LIST of integers (days)
time_points = [0, 30, 90, 180, 360]
```

#### `estimate_alpha_particle_radiotherapy_dosimetry`
```python
# Signature
estimate_alpha_particle_radiotherapy_dosimetry(biodistribution_data, radiation_parameters, output_file='dosimetry_results.csv')

# CRITICAL: biodistribution_data values are lists of (time_hours, percent_activity) TUPLES
biodistribution_data = {
    "tumor": [(1, 2.5), (4, 8.2), (24, 15.3), (48, 12.1)],
    "blood": [(1, 10.5), (4, 5.2), (24, 1.8), (48, 0.5)],
    "liver": [(1, 5.2), (4, 8.1), (24, 6.3), (48, 4.2)]
}

# radiation_parameters MUST include 'radionuclide' key
radiation_parameters = {
    "radionuclide": "Ac-225",  # REQUIRED
    "half_life_hours": 240.0,
    "energy_per_decay_MeV": 28.0,
    "radiation_weighting_factor": 20.0,
    "S_factors": {"tumor_tumor": 5.2e-13}
}
```

#### `run_3d_chondrogenic_aggregate_assay`
```python
# Signature
run_3d_chondrogenic_aggregate_assay(chondrocyte_cells, test_compounds, culture_duration_days=21, measurement_intervals=7)

# chondrocyte_cells: dict with 'source', 'passage_number', 'cell_density'
chondrocyte_cells = {
    "source": "human articular cartilage",
    "passage_number": 3,
    "cell_density": 250000
}

# test_compounds: LIST of dicts with 'name', 'concentration', 'vehicle'
test_compounds = [
    {"name": "TGF-β3", "concentration": "10 ng/mL", "vehicle": "PBS + 0.1% BSA"}
]
```

---

### 3. SYNTHETIC BIOLOGY

#### `create_biochemical_network_sbml_model`
```python
# Signature
create_biochemical_network_sbml_model(reaction_network, kinetic_parameters, output_file='biochemical_model.xml')

# CRITICAL: 'reactants' and 'products' are DICTS with stoichiometry, NOT lists
reaction_network = [
    {
        "id": "R1",
        "name": "Glucose uptake",
        "reactants": {"Glucose_ext": 1},  # species: stoichiometry
        "products": {"Glucose": 1},
        "reversible": False
    }
]

# kinetic_parameters: maps reaction IDs to law_type and parameters
kinetic_parameters = {
    "R1": {
        "law_type": "mass_action",  # or "michaelis_menten"
        "parameters": {"k_forward": 0.1}
    }
}
```

---

### 4. SYSTEMS BIOLOGY

#### `query_chatnt`
```python
# Signature - REQUIRES BOTH question AND sequence
query_chatnt(question, sequence, device=-1)

# Usage
result = systems_biology.query_chatnt(
    question="What is the GC content of this sequence?",
    sequence="ATGCATGCATGC"
)
```

#### `simulate_renin_angiotensin_system_dynamics`
```python
# Signature
simulate_renin_angiotensin_system_dynamics(initial_concentrations, rate_constants, feedback_params,
                                           simulation_time=48, time_points=100)

# CRITICAL: initial_concentrations needs ALL these keys
initial_concentrations = {
    "renin": 1.0,
    "angiotensinogen": 100.0,
    "angiotensin_I": 0.0,        # REQUIRED - often forgotten
    "angiotensin_II": 0.0,
    "ACE2_angiotensin_II": 0.0,
    "angiotensin_1_7": 0.0
}

rate_constants = {
    "k_ren": 0.1,   # renin production
    "k_agt": 0.5,   # angiotensinogen production
    "k_ace": 0.3,   # ACE conversion rate
    "k_ace2": 0.2,  # ACE2 conversion rate
    "k_at1r": 0.15, # AT1R binding rate
    "k_mas": 0.1    # Mas receptor binding rate
}

feedback_params = {
    "fb_ang_II": 0.05,  # angiotensin II feedback
    "fb_ace2": 0.03     # ACE2 feedback
}
```

#### `simulate_metabolic_network_perturbation`
```python
# Signature
simulate_metabolic_network_perturbation(model_file, initial_concentrations, perturbation_params,
                                        simulation_time=100, time_points=1000)

# CRITICAL: perturbation_params needs 'time', 'metabolite', 'factor' keys
perturbation_params = {
    "time": 50.0,       # when to apply perturbation
    "metabolite": "A",  # which metabolite to perturb
    "factor": 2.0       # multiplication factor
}
```

---

### 5. IMMUNOLOGY

#### `analyze_ebv_antibody_titers`
```python
# Signature
analyze_ebv_antibody_titers(raw_od_data, standard_curve_data, sample_metadata, output_dir='./')

# raw_od_data: dict with sample_id as keys, values are dicts of antibody_type: OD_value
raw_od_data = {
    "patient_001": {
        "VCA_IgG": 1.85, "VCA_IgM": 0.32,
        "EA_IgG": 0.95, "EA_IgM": 0.18,
        "EBNA1_IgG": 1.42, "EBNA1_IgM": 0.08
    }
}

# standard_curve_data: dict with antibody_type: [(concentration, OD), ...]
standard_curve_data = {
    "VCA_IgG": [(0, 0.05), (10, 0.25), (50, 0.85), (100, 1.5)],
    "VCA_IgM": [(0, 0.04), (10, 0.22), (50, 0.78), (100, 1.4)]
    # ... all antibody types
}
```

#### `estimate_cell_cycle_phase_durations`
```python
# Signature
estimate_cell_cycle_phase_durations(flow_cytometry_data, initial_estimates)

# CRITICAL: flow_cytometry_data is dict with specific keys, NOT a file path
flow_cytometry_data = {
    "time_points": [0, 2, 4, 6, 8, 10],  # hours
    "edu_positive": [5, 8, 14, 22, 28, 32],  # percentages
    "brdu_positive": [3, 6, 11, 17, 21, 25],
    "double_positive": [1, 3, 7, 12, 15, 18]
}

initial_estimates = {
    "g1_duration": 10.0,    # hours
    "s_duration": 8.0,
    "g2m_duration": 4.0,
    "death_rate": 0.01      # fraction per hour
}
```

---

### 6. BIOENGINEERING

#### `decode_behavior_from_neural_trajectories`
```python
# Signature
decode_behavior_from_neural_trajectories(neural_data, behavioral_data, n_components=10, output_dir='./')

# CRITICAL: neural_data is 2D (n_timepoints, n_neurons), NOT 3D
neural_data = np.random.randn(500, 50)  # 500 timepoints, 50 neurons

# behavioral_data is 2D (n_timepoints, n_behavioral_variables)
behavioral_data = np.random.randn(500, 3)  # 500 timepoints, 3 variables (x, y, speed)
```

---

### 7. GENETICS

#### `simulate_demographic_history`
```python
# Signature
simulate_demographic_history(num_samples=10, sequence_length=100000, recombination_rate=1e-08,
                            mutation_rate=1e-08, demographic_model='constant', demographic_params=None,
                            coalescent_model='kingman', beta_coalescent_param=None, random_seed=None,
                            output_file='simulated_sequences.vcf')

# demographic_params format for "constant" model
demographic_params = {"N": 10000}  # just population size

# demographic_params format for "bottleneck" model
demographic_params = {
    "N_initial": 10000,
    "N_bottleneck": 1000,
    "T_bottleneck": 500,    # generations ago
    "T_recovery": 100       # generations ago
}
```

#### `bayesian_finemapping_with_deep_vi`
```python
# Signature
bayesian_finemapping_with_deep_vi(gwas_summary_path, ld_matrix, n_iterations=5000, learning_rate=0.01,
                                  hidden_dim=64, credible_threshold=0.95)

# CRITICAL: GWAS file MUST have these columns:
# variant_id, effect_size, pvalue, se
# Example TSV format:
# variant_id    effect_size    pvalue    se
# rs1000000     0.05           1e-5      0.01
```

---

## Common Issues and Solutions

### Issue 1: "string indices must be integers"
**Cause:** Passing a dict where a list is expected, or vice versa
**Solution:** Check docstring - is the parameter a LIST of dicts or a single dict?

### Issue 2: "got an unexpected keyword argument"
**Cause:** Using parameter names that don't match the function signature
**Solution:** Use `inspect.signature(func)` to get exact parameter names

### Issue 3: "missing N required positional arguments"
**Cause:** Not providing all required parameters
**Solution:** Check function signature for all non-default parameters

### Issue 4: "'key' not found" errors
**Cause:** Missing required keys in dict parameters
**Solution:** Check docstring for required dict keys (e.g., 'radionuclide' for dosimetry)

### Issue 5: "Found array with dim 3, while dim <= 2 is required"
**Cause:** Passing 3D array where 2D is expected (common with neural data)
**Solution:** Reshape data to (n_timepoints, n_features), not (n_trials, n_timepoints, n_features)

### Issue 6: "Duplicate population name" (v5 fix)
**Cause:** Bug in `genetics.simulate_demographic_history` - adds pop0 twice for "constant" model
**Solution:** Use "expansion" model with N_initial=N_final as workaround:
```python
demographic_params = {"N_initial": 10000, "N_final": 10000, "T_expansion": 100}
```

### Issue 7: Calibration data format mismatch (v5 fix)
**Cause:** Function expects nested dict with "factor" and "limit" keys
**Solution:** For `analyze_arsenic_speciation_hplc_icpms`:
```python
calibration_data = {
    "As(III)": {"factor": 0.85, "limit": 0.1},
    "As(V)": {"factor": 0.92, "limit": 0.1},
    # NOT: [("conc", "signal"), ...]
}
```

### Issue 8: Standard curve key simplification (v5 fix)
**Cause:** Function looks up by base type ("IgG", "IgM") not full name
**Solution:** For `analyze_ebv_antibody_titers`:
```python
standard_curve_data = {
    "IgG": [(0, 0.05), (10, 0.25), ...],  # NOT "VCA_IgG"
    "IgM": [(0, 0.04), (10, 0.22), ...]   # NOT "VCA_IgM"
}
```

---

## Tool-Specific Requirements

### scRNA-seq Functions (UPDATED v7)

#### `create_harmony_embeddings_scRNA` ✅ WORKS
```python
# Signature
create_harmony_embeddings_scRNA(adata_filename, batch_key, data_dir)

# Requirements:
# - AnnData file with X_pca computed (run sc.pp.pca first)
# - obs column with batch information

# Usage
result = genomics.create_harmony_embeddings_scRNA(
    adata_filename='data.h5ad',
    batch_key='batch',
    data_dir='/path/to/data'
)
# Output: Creates harmony_emb_data.h5ad with X_harmony in obsm
```

#### `create_scvi_embeddings_scRNA` ✅ WORKS
```python
# Signature
create_scvi_embeddings_scRNA(adata_filename, batch_key, label_key, data_dir)

# Requirements:
# - AnnData file with normalized, log-transformed data
# - obs columns for batch and label (cell type)

# Usage
result = genomics.create_scvi_embeddings_scRNA(
    adata_filename='data.h5ad',
    batch_key='batch',
    label_key='celltype',
    data_dir='/path/to/data'
)
# Output: Creates scvi_emb_data.h5ad with X_scVI and X_scANVI in obsm
```

#### `annotate_celltype_scRNA` ⚠️ NEEDS API KEY
```python
# Signature
annotate_celltype_scRNA(adata_filename, data_dir, data_info, data_lake_path,
                        cluster='leiden', llm='claude-3-5-sonnet-20241022', composition=None)

# Requirements:
# - ANTHROPIC_API_KEY environment variable
# - czi_census_datasets_v4.parquet in data_lake_path
# - AnnData with leiden clustering

# Usage
result = genomics.annotate_celltype_scRNA(
    adata_filename='data.h5ad',
    data_dir='/path/to/data',
    data_info='homo sapiens, blood, normal',
    data_lake_path='/path/to/data_lake',
    cluster='leiden'
)
```

### Tools Requiring External Binaries (ARM64 Issues)
- `pharmacology.docking_autodock_vina` - Requires TDC with rdkit<2024.3.1, tiledb (ARM64 incompatible)
- `pharmacology.run_autosite` - Requires autosite binary from ADFR suite (not available for ARM64)

### Tools Requiring API Tokens
- `genomics.annotate_celltype_scRNA` - ANTHROPIC_API_KEY
- `protocols.get_protocol_details` - PROTOCOLS_IO_ACCESS_TOKEN

---

## Testing Patterns

### Pattern 1: Image-based Analysis
```python
from PIL import Image
import numpy as np

# Create test image
img = np.random.randint(50, 200, (256, 256), dtype=np.uint8)
img_path = "/tmp/test_image.png"
Image.fromarray(img).save(img_path)

# Use with function
result = module.analyze_image(img_path)
```

### Pattern 2: Mock AnnData for scRNA (UPDATED v7)
```python
import scanpy as sc
import pandas as pd
import numpy as np

# Create minimal AnnData with required structure
np.random.seed(42)
n_cells, n_genes = 100, 200

# Use count-like data (Poisson distribution mimics real scRNA counts)
X = np.random.poisson(lam=3, size=(n_cells, n_genes)).astype(np.float32)

adata = sc.AnnData(X)
adata.obs_names = [f'cell_{i}' for i in range(n_cells)]
adata.var_names = [f'gene_{i}' for i in range(n_genes)]

# REQUIRED: Add batch and label columns
adata.obs['batch'] = np.random.choice(['batch1', 'batch2'], n_cells)
adata.obs['celltype'] = np.random.choice(['T_cell', 'B_cell', 'Monocyte'], n_cells)
adata.obs['leiden'] = pd.Categorical(np.random.choice(['0', '1', '2'], n_cells))

# REQUIRED FOR HARMONY: Run preprocessing to compute X_pca
sc.pp.normalize_total(adata)
sc.pp.log1p(adata)
sc.pp.highly_variable_genes(adata, n_top_genes=50)
sc.pp.pca(adata, n_comps=30)  # Creates adata.obsm['X_pca']

adata.write('/tmp/scrna/test_adata.h5ad')

# Now can use with:
# genomics.create_harmony_embeddings_scRNA('test_adata.h5ad', 'batch', '/tmp/scrna')
# genomics.create_scvi_embeddings_scRNA('test_adata.h5ad', 'batch', 'celltype', '/tmp/scrna')
```

### Pattern 3: Mock Sequence Files
```python
# FASTA
with open("/tmp/mock.fasta", 'w') as f:
    f.write(">seq1\nATGCATGCATGC\n")

# BED
with open("/tmp/mock.bed", 'w') as f:
    f.write("chr1\t100\t200\tpeak1\t100\t+\n")

# PDB
with open("/tmp/mock.pdb", 'w') as f:
    f.write("ATOM      1  N   ALA A   1       0.000   0.000   0.000  1.00 20.00           N\n")
    f.write("END\n")
```

### Pattern 4: Time-Series Data
```python
# For biodistribution, use list of (time, value) tuples
data = {
    "tissue1": [(1, 10.0), (4, 8.0), (24, 4.0)],
    "tissue2": [(1, 5.0), (4, 7.0), (24, 3.0)]
}
```

---

## Version History

| Version | Date | Pass Rate | Changes |
|---------|------|-----------|---------|
| v1 | 2026-01-19 | 33% | Initial test |
| v2 | 2026-01-19 | 47% | Some signature fixes |
| v3 | 2026-01-19 | 62% | More fixes + dependencies |
| v4 | 2026-01-19 | 85% | Exact docstring formats |
| v5 | 2026-01-19 | 91% | Source code analysis + bug workarounds |
| **v7** | 2026-01-19 | **95%** | scRNA functions (Harmony, scVI) now work |

### v7 Key Findings
- `create_harmony_embeddings_scRNA` - Does NOT need external models, just proper AnnData with X_pca
- `create_scvi_embeddings_scRNA` - Does NOT need external models, trains from scratch
- `annotate_celltype_scRNA` - Works but needs ANTHROPIC_API_KEY at runtime
- Docking tools (vina, autosite) - ARM64 incompatible due to TDC/tiledb/autosite binaries

---

## Files Reference

| File | Purpose |
|------|---------|
| `Biomni/tests/test_skipped_tools_v5.py` | Test with 91% pass rate (source code analysis) |
| `Biomni/tests/test_skipped_tools_v7.py` | Test with 95% pass rate (scRNA working) |
| `Biomni/tests/exhaustive_biomni_test_v4_NO_SKIP.py` | Full exhaustive test |
| `docs/BIOMNI_TROUBLESHOOTING_LOG.md` | Detailed troubleshooting documentation |
| `20260119_BIOMNI_SKIPPED_TOOLS_TEST_SUMMARY.md` | Summary of test progression |

---

## Contact

For questions about Biomni tools, refer to:
- Function docstrings: `print(func.__doc__)`
- Function signatures: `import inspect; print(inspect.signature(func))`
- Source code: `/opt/biomni/src/biomni/tool/`
