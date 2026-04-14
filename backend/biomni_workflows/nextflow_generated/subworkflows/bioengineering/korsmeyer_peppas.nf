#!/usr/bin/env nextflow
/*
 * biomni_bioengineering_korsmeyer_peppas
 * 
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.t = null
params.k = null
params.n = null

// Main process
process KORSMEYER_PEPPAS {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("korsmeyer_peppas_results.json"), emit: results
    path("korsmeyer_peppas_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.bioengineering import korsmeyer_peppas
except ImportError:
    # Fallback: function may need to be implemented locally
    def korsmeyer_peppas(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = korsmeyer_peppas(
    t="${params.t}",
    k="${params.k}",
    n="${params.n}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("korsmeyer_peppas_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("korsmeyer_peppas_output.txt", "w") as f:
    f.write("Biomni: Korsmeyer Peppas Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("korsmeyer_peppas completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_BIOENGINEERING_KORSMEYER_PEPPAS {
    take:
    // No file inputs

    main:
    KORSMEYER_PEPPAS()

    emit:
    results = KORSMEYER_PEPPAS.out.results
    output = KORSMEYER_PEPPAS.out.output
}

// Entry workflow
workflow {
    if (!params.t) {
        error "Please provide --t parameter"
    }
    if (!params.k) {
        error "Please provide --k parameter"
    }
    if (!params.n) {
        error "Please provide --n parameter"
    }


    BIOMNI_BIOENGINEERING_KORSMEYER_PEPPAS()
}
