# Nextflow Biomni Workflow Guide

**Version:** 1.0
**Date:** 2026-01-23
**Author:** BioMate Team

## Overview

This directory contains 237 Nextflow workflows generated from Galaxy Biomni tools. Each workflow calls functions from the `biomni.tool` Python module within a Docker container.

## Quick Start

### Prerequisites

- Nextflow 21.10+ (tested with 25.10.0)
- Docker
- biomate/biomni-tools:latest Docker image

### Running a Workflow

```bash
cd /home/yzhang/biomate/backend/biomni_workflows/nextflow

# Example: Run design_primer
nextflow run subworkflows/molecular_biology/design_primer.nf \
  --sequence "ATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCG" \
  --start_pos 10 \
  -with-docker biomate/biomni-tools:latest
```

### Output

Each workflow produces:
- `{function_name}_results.json` - JSON output with results
- `{function_name}_output.txt` - Human-readable text output

## Directory Structure

```
nextflow/
├── nextflow.config          # Global Nextflow configuration
├── subworkflows/            # Individual tool workflows (237 total)
│   ├── biochemistry/        # 9 workflows
│   ├── bioengineering/      # 13 workflows
│   ├── bioimaging/          # 22 workflows
│   ├── biophysics/          # 3 workflows
│   ├── cancer_biology/      # 7 workflows
│   ├── cell_biology/        # 5 workflows
│   ├── database/            # 5 workflows
│   ├── genetics/            # 11 workflows
│   ├── genomics/            # 25 workflows
│   ├── glycoengineering/    # 3 workflows
│   ├── immunology/          # 13 workflows
│   ├── lab_automation/      # 6 workflows
│   ├── literature/          # 4 workflows
│   ├── microbiology/        # 16 workflows
│   ├── molecular_biology/   # 26 workflows
│   ├── pathology/           # 7 workflows
│   ├── pharmacology/        # 25 workflows
│   ├── physiology/          # 14 workflows
│   ├── synthetic_biology/   # 11 workflows
│   └── systems_biology/     # 12 workflows
├── workflows/               # Legacy workflow stubs (deprecated)
└── docs/                    # Documentation
```

## Verified Working Workflows

### molecular_biology/design_primer.nf ✅

Design PCR primers for a given sequence.

```bash
nextflow run subworkflows/molecular_biology/design_primer.nf \
  --sequence "ATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCG" \
  --start_pos 10 \
  -with-docker biomate/biomni-tools:latest
```

**Parameters:**
- `--sequence` (required): DNA sequence
- `--start_pos` (required): Starting position for primer
- `--primer_length` (default: 20): Primer length
- `--min_gc` (default: 0.4): Minimum GC content
- `--max_gc` (default: 0.6): Maximum GC content
- `--min_tm` (default: 55.0): Minimum melting temperature
- `--max_tm` (default: 65.0): Maximum melting temperature

**Output:**
```json
{
  "sequence": "CGATCGATCGATCGATCGAT",
  "position": 10,
  "gc": 0.5,
  "tm": 60.0,
  "score": 0.0
}
```

### molecular_biology/annotate_plasmid.nf ✅

Annotate features on a plasmid sequence.

```bash
nextflow run subworkflows/molecular_biology/annotate_plasmid.nf \
  --sequence "ATGAAACGCATTAGCACCACCATTACCACCACCATCACC..." \
  --plasmid_name "my_plasmid" \
  -with-docker biomate/biomni-tools:latest
```

## Available Functions by Domain

### molecular_biology (20+ functions)
- align_sequences
- annotate_open_reading_frames
- annotate_plasmid
- design_golden_gate_oligos
- design_knockout_sgrna
- design_primer ✅
- design_verification_primers
- digest_sequence
- find_restriction_enzymes
- find_restriction_sites
- find_sequence_mutations
- get_bacterial_transformation_protocol
- get_gene_coding_sequence
- get_golden_gate_assembly_protocol
- get_oligo_annealing_protocol
- get_plasmid_sequence
- golden_gate_assembly
- pcr_simple

### biochemistry (6 functions)
- analyze_circular_dichroism_spectra
- analyze_enzyme_kinetics_assay
- analyze_itc_binding_thermodynamics
- analyze_protease_kinetics
- analyze_protein_conservation
- analyze_rna_secondary_structure_features

### microbiology (12 functions)
- analyze_arsenic_speciation_hplc_icpms
- annotate_bacterial_genome
- count_bacterial_colonies
- enumerate_bacterial_cfu_by_serial_dilution
- model_bacterial_growth_dynamics
- optimize_anaerobic_digestion_process
- predict_rna_secondary_structure
- quantify_biofilm_biomass_crystal_violet
- segment_and_analyze_microbial_cells
- segment_cells_with_deep_learning
- simulate_generalized_lotka_volterra_dynamics
- simulate_microbial_population_dynamics

## Workflow Template Structure

Each workflow follows this structure:

```nextflow
#!/usr/bin/env nextflow

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.param1 = null
params.param2 = 'default_value'

// Main process
process FUNCTION_NAME {
    container 'biomate/biomni-tools:latest'
    publishDir "${params.outdir}", mode: 'copy'

    output:
    path("function_name_results.json"), emit: results
    path("function_name_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.domain import function_name

result = function_name(
    param1="${params.param1}",
    param2=${params.param2}
)

with open("function_name_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)
PYEOF
    """
}

// Workflow
workflow {
    FUNCTION_NAME()
}
```

## Docker Container

The workflows use the `biomate/biomni-tools:latest` Docker image which includes:
- Python 3.11+
- Biomni tool library at `/opt/biomni/src/biomni/`
- All required dependencies (BioPython, NumPy, SciPy, etc.)

## Extending Workflows

### Adding New Workflows

1. Create XML tool definition in Galaxy format
2. Run the generator:
   ```bash
   python3 backend/lib/galaxy/ai/generate_biomni_nextflow.py
   ```
3. Copy generated workflows:
   ```bash
   cp -r backend/biomni_workflows/nextflow_generated/subworkflows/* \
        backend/biomni_workflows/nextflow/subworkflows/
   ```

### Customizing Workflows

To add additional processing steps, modify the workflow section:

```nextflow
workflow {
    FUNCTION_NAME()

    // Add post-processing
    CUSTOM_PROCESS(FUNCTION_NAME.out.results)
}
```

## Troubleshooting

### Common Issues

1. **Function not found**: The biomni function may not exist in the container. Check available functions with:
   ```bash
   docker run --rm biomate/biomni-tools:latest \
     python3 -c "from biomni.tool.domain import *; print(dir())"
   ```

2. **Parameter errors**: Check the workflow file for required parameters and their types.

3. **Docker permission**: Ensure Docker is running and accessible.

### Logs

Check Nextflow logs:
```bash
cat .nextflow.log
```

Check process-specific logs:
```bash
cat work/{hash}/.command.err
cat work/{hash}/.command.out
```

## Generator Script

The workflows are generated by:
`/home/yzhang/biomate/backend/lib/galaxy/ai/generate_biomni_nextflow.py`

Features:
- Parses Galaxy XML tool definitions
- Handles embedded quotes in XML attributes
- Converts Galaxy parameters to Nextflow params
- Generates proper Python heredoc with biomni imports
- Handles boolean type conversion (Nextflow true/false → Python True/False)

## Contact

For issues or questions, contact the BioMate team.
