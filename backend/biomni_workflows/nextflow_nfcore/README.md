# Biomni Nextflow Modules (nf-core style)

Nextflow modules generated from tested Galaxy wrappers. These modules are self-contained
and do not require the biomni Python module - they embed the actual function implementation
directly in the workflow.

## Quick Start

```bash
# Run a workflow
nextflow run subworkflows/microbiology/model_bacterial_growth_dynamics/main.nf \
  --initial_population 1000 \
  --growth_rate 0.5 \
  --clearance_rate 0.1 \
  --niche_size 100000 \
  -with-docker biomate/biomni-tools:latest
```

## Generated Workflows

237 workflows across 20 domains:

| Domain | Workflows |
|--------|-----------|
| biochemistry | 9 |
| bioengineering | 13 |
| bioimaging | 22 |
| biophysics | 3 |
| cancer_biology | 7 |
| cell_biology | 5 |
| database | 5 |
| genetics | 11 |
| genomics | 25 |
| glycoengineering | 3 |
| immunology | 13 |
| lab_automation | 6 |
| literature | 4 |
| microbiology | 16 |
| molecular_biology | 26 |
| pathology | 7 |
| pharmacology | 25 |
| physiology | 14 |
| synthetic_biology | 11 |
| systems_biology | 12 |

## Module Structure

Each module follows nf-core conventions:

```
subworkflows/{domain}/{function_name}/
├── main.nf          # Nextflow workflow with embedded Python
└── meta.yml         # Module metadata
```

## Key Features

1. **Self-contained** - No external dependencies on biomni module
2. **nf-core compatible** - Uses tuple input/output patterns
3. **Docker support** - Uses `biomate/biomni-tools:latest` container
4. **Auto type conversion** - String parameters converted to appropriate types
5. **JSON + text output** - Results in both structured and human-readable formats
6. **Version tracking** - `versions.yml` output for reproducibility

## Using as Module

Include in your pipeline:

```nextflow
include { MODEL_BACTERIAL_GROWTH_DYNAMICS } from './subworkflows/microbiology/model_bacterial_growth_dynamics/main'

workflow {
    ch_input = Channel.of([id: 'sample1'])
    MODEL_BACTERIAL_GROWTH_DYNAMICS(ch_input)
}
```

## Generation

These workflows were generated from Galaxy wrappers using:

```bash
python3 lib/galaxy/ai/generate_nfcore_biomni.py \
  --galaxy-dir biomni_workflows/galaxy/tools/biomni \
  --output-dir biomni_workflows/nextflow_nfcore
```

## Tested Workflows

- `model_bacterial_growth_dynamics` - Bacterial growth ODE simulation (PASS)
- `digest_sequence` - Restriction enzyme digestion (PASS)
- `analyze_enzyme_kinetics_assay` - Enzyme kinetics analysis (PASS)
- `gene_set_enrichment_analysis` - Gene enrichment analysis with gget (PASS)

## Parameter Formats

For list parameters, pass JSON arrays:
```bash
--enzyme_names '["EcoRI", "BamHI"]'
--genes '["TP53", "BRCA1"]'
--substrate_concentrations '[0.1, 0.2, 0.5, 1.0]'
```

For dict parameters, pass JSON objects:
```bash
--gating_strategy '{"HSCs": [["Lin", "<", 100], ["Sca1", ">", 1000]]}'
```

## Container

Uses `biomate/biomni-tools:latest` which includes:
- Python 3.x
- NumPy, SciPy, pandas
- BioPython
- Other bioinformatics dependencies
