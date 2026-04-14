#!/usr/bin/env nextflow
/*
 * biomni_bioengineering_analyze_calcium_imaging_data
 * Analyze calcium imaging data to quantify neuronal activity metrics.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.image_stack_path = null
params.output_dir = './'

// Main process
process ANALYZE_CALCIUM_IMAGING_DATA {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("analyze_calcium_imaging_data_results.json"), emit: results
    path("analyze_calcium_imaging_data_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.bioengineering import analyze_calcium_imaging_data

# Run the tool
try:
    result = analyze_calcium_imaging_data(
    image_stack_path="${params.image_stack_path}",
    output_dir="${params.output_dir}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("analyze_calcium_imaging_data_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("analyze_calcium_imaging_data_output.txt", "w") as f:
    f.write("Biomni: Analyze Calcium Imaging Data Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("analyze_calcium_imaging_data completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_BIOENGINEERING_ANALYZE_CALCIUM_IMAGING_DATA {
    take:
    // No file inputs

    main:
    ANALYZE_CALCIUM_IMAGING_DATA()

    emit:
    results = ANALYZE_CALCIUM_IMAGING_DATA.out.results
    output = ANALYZE_CALCIUM_IMAGING_DATA.out.output
}

// Entry workflow
workflow {
    if (!params.image_stack_path) {
        error "Please provide --image_stack_path parameter"
    }


    BIOMNI_BIOENGINEERING_ANALYZE_CALCIUM_IMAGING_DATA()
}
