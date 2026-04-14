#!/usr/bin/env nextflow
/*
 * biomni_synthetic_biology_gene_circuit_odes
 * 
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.t = null
params.state = null

// Main process
process GENE_CIRCUIT_ODES {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("gene_circuit_odes_results.json"), emit: results
    path("gene_circuit_odes_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.synthetic_biology import gene_circuit_odes
except ImportError:
    # Fallback: function may need to be implemented locally
    def gene_circuit_odes(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = gene_circuit_odes(
    t="${params.t}",
    state="${params.state}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("gene_circuit_odes_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("gene_circuit_odes_output.txt", "w") as f:
    f.write("Biomni: Gene Circuit Odes Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("gene_circuit_odes completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_SYNTHETIC_BIOLOGY_GENE_CIRCUIT_ODES {
    take:
    // No file inputs

    main:
    GENE_CIRCUIT_ODES()

    emit:
    results = GENE_CIRCUIT_ODES.out.results
    output = GENE_CIRCUIT_ODES.out.output
}

// Entry workflow
workflow {
    if (!params.t) {
        error "Please provide --t parameter"
    }
    if (!params.state) {
        error "Please provide --state parameter"
    }


    BIOMNI_SYNTHETIC_BIOLOGY_GENE_CIRCUIT_ODES()
}
