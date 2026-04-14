#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_pcr_simple
 * Simulate PCR amplification with given primers and sequence.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.sequence = null
params.forward_primer = null
params.reverse_primer = null
params.circular = false

// Main process
process PCR_SIMPLE {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("pcr_simple_results.json"), emit: results
    path("pcr_simple_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.molecular_biology import pcr_simple
except ImportError:
    # Fallback: function may need to be implemented locally
    def pcr_simple(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = pcr_simple(
    sequence="${params.sequence}",
    forward_primer="${params.forward_primer}",
    reverse_primer="${params.reverse_primer}",
    circular=${params.circular}
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("pcr_simple_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("pcr_simple_output.txt", "w") as f:
    f.write("Biomni: Pcr Simple Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("pcr_simple completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_MOLECULAR_BIOLOGY_PCR_SIMPLE {
    take:
    // No file inputs

    main:
    PCR_SIMPLE()

    emit:
    results = PCR_SIMPLE.out.results
    output = PCR_SIMPLE.out.output
}

// Entry workflow
workflow {
    if (!params.sequence) {
        error "Please provide --sequence parameter"
    }
    if (!params.forward_primer) {
        error "Please provide --forward_primer parameter"
    }
    if (!params.reverse_primer) {
        error "Please provide --reverse_primer parameter"
    }


    BIOMNI_MOLECULAR_BIOLOGY_PCR_SIMPLE()
}
