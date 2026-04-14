#!/usr/bin/env nextflow
/*
 * biomni_physiology_calculate_brain_adc_map
 * Calculate Apparent Diffusion Coefficient (ADC) map from diffusion-weighted MRI data.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.dwi_file_path = null
params.b_values = null
params.output_path = 'adc_map.nii.gz'
params.mask_file_path = null

// Main process
process CALCULATE_BRAIN_ADC_MAP {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("calculate_brain_adc_map_results.json"), emit: results
    path("calculate_brain_adc_map_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.physiology import calculate_brain_adc_map

# Run the tool
try:
    result = calculate_brain_adc_map(
    dwi_file_path="${params.dwi_file_path}",
    b_values="${params.b_values}",
    output_path="${params.output_path}",
    mask_file_path="${params.mask_file_path}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("calculate_brain_adc_map_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("calculate_brain_adc_map_output.txt", "w") as f:
    f.write("Biomni: Calculate Brain Adc Map Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("calculate_brain_adc_map completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_PHYSIOLOGY_CALCULATE_BRAIN_ADC_MAP {
    take:
    // No file inputs

    main:
    CALCULATE_BRAIN_ADC_MAP()

    emit:
    results = CALCULATE_BRAIN_ADC_MAP.out.results
    output = CALCULATE_BRAIN_ADC_MAP.out.output
}

// Entry workflow
workflow {
    if (!params.dwi_file_path) {
        error "Please provide --dwi_file_path parameter"
    }
    if (!params.b_values) {
        error "Please provide --b_values parameter"
    }


    BIOMNI_PHYSIOLOGY_CALCULATE_BRAIN_ADC_MAP()
}
