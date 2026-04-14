#!/usr/bin/env nextflow
/*
 * biomni_microbiology_enumerate_bacterial_cfu_by_serial_dilution
 * Quantify bacterial concentration (CFU/mL) using serial dilutions and spot plating.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.initial_sample_volume_ml = '1.0'
params.estimated_concentration = '100000000.0'
params.dilution_factor = '10'
params.num_dilutions = '8'
params.spots_per_dilution = '3'
params.output_file = 'cfu_enumeration_results.csv'

// Main process
process ENUMERATE_BACTERIAL_CFU_BY_SERIAL_DILUTION {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("enumerate_bacterial_cfu_by_serial_dilution_results.json"), emit: results
    path("enumerate_bacterial_cfu_by_serial_dilution_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.microbiology import enumerate_bacterial_cfu_by_serial_dilution

# Run the tool
try:
    result = enumerate_bacterial_cfu_by_serial_dilution(
    initial_sample_volume_ml="${params.initial_sample_volume_ml}",
    estimated_concentration="${params.estimated_concentration}",
    dilution_factor="${params.dilution_factor}",
    num_dilutions="${params.num_dilutions}",
    spots_per_dilution="${params.spots_per_dilution}",
    output_file="${params.output_file}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("enumerate_bacterial_cfu_by_serial_dilution_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("enumerate_bacterial_cfu_by_serial_dilution_output.txt", "w") as f:
    f.write("Biomni: Enumerate Bacterial Cfu By Serial Dilution Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("enumerate_bacterial_cfu_by_serial_dilution completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_MICROBIOLOGY_ENUMERATE_BACTERIAL_CFU_BY_SERIAL_DILUTION {
    take:
    // No file inputs

    main:
    ENUMERATE_BACTERIAL_CFU_BY_SERIAL_DILUTION()

    emit:
    results = ENUMERATE_BACTERIAL_CFU_BY_SERIAL_DILUTION.out.results
    output = ENUMERATE_BACTERIAL_CFU_BY_SERIAL_DILUTION.out.output
}

// Entry workflow
workflow {



    BIOMNI_MICROBIOLOGY_ENUMERATE_BACTERIAL_CFU_BY_SERIAL_DILUTION()
}
