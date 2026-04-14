#!/usr/bin/env nextflow
/*
 * biomni_bioengineering_default_whole_cell_model
 * 
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.t = null
params.y = null
params.params = null

// Main process
process DEFAULT_WHOLE_CELL_MODEL {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("default_whole_cell_model_results.json"), emit: results
    path("default_whole_cell_model_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.bioengineering import default_whole_cell_model

# Run the tool
try:
    result = default_whole_cell_model(
    t="${params.t}",
    y="${params.y}",
    params="${params.params}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("default_whole_cell_model_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("default_whole_cell_model_output.txt", "w") as f:
    f.write("Biomni: Default Whole Cell Model Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("default_whole_cell_model completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_BIOENGINEERING_DEFAULT_WHOLE_CELL_MODEL {
    take:
    // No file inputs

    main:
    DEFAULT_WHOLE_CELL_MODEL()

    emit:
    results = DEFAULT_WHOLE_CELL_MODEL.out.results
    output = DEFAULT_WHOLE_CELL_MODEL.out.output
}

// Entry workflow
workflow {
    if (!params.t) {
        error "Please provide --t parameter"
    }
    if (!params.y) {
        error "Please provide --y parameter"
    }
    if (!params.params) {
        error "Please provide --params parameter"
    }


    BIOMNI_BIOENGINEERING_DEFAULT_WHOLE_CELL_MODEL()
}
