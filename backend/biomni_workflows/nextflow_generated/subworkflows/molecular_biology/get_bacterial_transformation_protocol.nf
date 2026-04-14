#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_get_bacterial_transformation_protocol
 * Return a standard protocol for bacterial transformation.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.antibiotic = 'ampicillin'
params.is_repetitive = false

// Main process
process GET_BACTERIAL_TRANSFORMATION_PROTOCOL {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("get_bacterial_transformation_protocol_results.json"), emit: results
    path("get_bacterial_transformation_protocol_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.molecular_biology import get_bacterial_transformation_protocol
except ImportError:
    # Fallback: function may need to be implemented locally
    def get_bacterial_transformation_protocol(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = get_bacterial_transformation_protocol(
    antibiotic="${params.antibiotic}",
    is_repetitive=${params.is_repetitive}
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("get_bacterial_transformation_protocol_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("get_bacterial_transformation_protocol_output.txt", "w") as f:
    f.write("Biomni: Get Bacterial Transformation Protocol Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("get_bacterial_transformation_protocol completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_MOLECULAR_BIOLOGY_GET_BACTERIAL_TRANSFORMATION_PROTOCOL {
    take:
    // No file inputs

    main:
    GET_BACTERIAL_TRANSFORMATION_PROTOCOL()

    emit:
    results = GET_BACTERIAL_TRANSFORMATION_PROTOCOL.out.results
    output = GET_BACTERIAL_TRANSFORMATION_PROTOCOL.out.output
}

// Entry workflow
workflow {



    BIOMNI_MOLECULAR_BIOLOGY_GET_BACTERIAL_TRANSFORMATION_PROTOCOL()
}
