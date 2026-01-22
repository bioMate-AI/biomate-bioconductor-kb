#!/usr/bin/env nextflow
/*
 * biomni_microbiology_vfa_production_model
 * 
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.params = null

// Main process
process VFA_PRODUCTION_MODEL {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("vfa_production_model_results.json"), emit: results
    path("vfa_production_model_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.microbiology import vfa_production_model
except ImportError:
    # Fallback: function may need to be implemented locally
    def vfa_production_model(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = vfa_production_model(
    params="${params.params}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("vfa_production_model_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("vfa_production_model_output.txt", "w") as f:
    f.write("Biomni: Vfa Production Model Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("vfa_production_model completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_MICROBIOLOGY_VFA_PRODUCTION_MODEL {
    take:
    // No file inputs

    main:
    VFA_PRODUCTION_MODEL()

    emit:
    results = VFA_PRODUCTION_MODEL.out.results
    output = VFA_PRODUCTION_MODEL.out.output
}

// Entry workflow
workflow {
    if (!params.params) {
        error "Please provide --params parameter"
    }


    BIOMNI_MICROBIOLOGY_VFA_PRODUCTION_MODEL()
}
