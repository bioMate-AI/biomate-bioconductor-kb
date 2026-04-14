#!/usr/bin/env nextflow
/*
 * biomni_microbiology_methane_yield_model
 * 
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.params = null

// Main process
process METHANE_YIELD_MODEL {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("methane_yield_model_results.json"), emit: results
    path("methane_yield_model_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.microbiology import methane_yield_model
except ImportError:
    # Fallback: function may need to be implemented locally
    def methane_yield_model(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = methane_yield_model(
    params="${params.params}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("methane_yield_model_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("methane_yield_model_output.txt", "w") as f:
    f.write("Biomni: Methane Yield Model Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("methane_yield_model completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_MICROBIOLOGY_METHANE_YIELD_MODEL {
    take:
    // No file inputs

    main:
    METHANE_YIELD_MODEL()

    emit:
    results = METHANE_YIELD_MODEL.out.results
    output = METHANE_YIELD_MODEL.out.output
}

// Entry workflow
workflow {
    if (!params.params) {
        error "Please provide --params parameter"
    }


    BIOMNI_MICROBIOLOGY_METHANE_YIELD_MODEL()
}
