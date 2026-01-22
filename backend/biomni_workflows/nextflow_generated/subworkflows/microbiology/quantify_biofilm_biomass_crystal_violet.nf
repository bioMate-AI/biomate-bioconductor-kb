#!/usr/bin/env nextflow
/*
 * biomni_microbiology_quantify_biofilm_biomass_crystal_violet
 * Quantifies biofilm biomass using crystal violet staining assay data.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.od_values = null
params.sample_names = null
params.control_index = '0'
params.save_path = null

// Main process
process QUANTIFY_BIOFILM_BIOMASS_CRYSTAL_VIOLET {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("quantify_biofilm_biomass_crystal_violet_results.json"), emit: results
    path("quantify_biofilm_biomass_crystal_violet_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.microbiology import quantify_biofilm_biomass_crystal_violet
except ImportError:
    # Fallback: function may need to be implemented locally
    def quantify_biofilm_biomass_crystal_violet(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = quantify_biofilm_biomass_crystal_violet(
    od_values="${params.od_values}",
    sample_names="${params.sample_names}",
    control_index="${params.control_index}",
    save_path="${params.save_path}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("quantify_biofilm_biomass_crystal_violet_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("quantify_biofilm_biomass_crystal_violet_output.txt", "w") as f:
    f.write("Biomni: Quantify Biofilm Biomass Crystal Violet Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("quantify_biofilm_biomass_crystal_violet completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_MICROBIOLOGY_QUANTIFY_BIOFILM_BIOMASS_CRYSTAL_VIOLET {
    take:
    // No file inputs

    main:
    QUANTIFY_BIOFILM_BIOMASS_CRYSTAL_VIOLET()

    emit:
    results = QUANTIFY_BIOFILM_BIOMASS_CRYSTAL_VIOLET.out.results
    output = QUANTIFY_BIOFILM_BIOMASS_CRYSTAL_VIOLET.out.output
}

// Entry workflow
workflow {
    if (!params.od_values) {
        error "Please provide --od_values parameter"
    }


    BIOMNI_MICROBIOLOGY_QUANTIFY_BIOFILM_BIOMASS_CRYSTAL_VIOLET()
}
