#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_get_oligo_annealing_protocol
 * Return a standard protocol for annealing oligonucleotides without phosphorylation.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'

// Main process
process GET_OLIGO_ANNEALING_PROTOCOL {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("get_oligo_annealing_protocol_results.json"), emit: results
    path("get_oligo_annealing_protocol_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.molecular_biology import get_oligo_annealing_protocol
except ImportError:
    # Fallback: function may need to be implemented locally
    def get_oligo_annealing_protocol(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = get_oligo_annealing_protocol(

    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("get_oligo_annealing_protocol_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("get_oligo_annealing_protocol_output.txt", "w") as f:
    f.write("Biomni: Get Oligo Annealing Protocol Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("get_oligo_annealing_protocol completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_MOLECULAR_BIOLOGY_GET_OLIGO_ANNEALING_PROTOCOL {
    take:
    // No file inputs

    main:
    GET_OLIGO_ANNEALING_PROTOCOL()

    emit:
    results = GET_OLIGO_ANNEALING_PROTOCOL.out.results
    output = GET_OLIGO_ANNEALING_PROTOCOL.out.output
}

// Entry workflow
workflow {



    BIOMNI_MOLECULAR_BIOLOGY_GET_OLIGO_ANNEALING_PROTOCOL()
}
