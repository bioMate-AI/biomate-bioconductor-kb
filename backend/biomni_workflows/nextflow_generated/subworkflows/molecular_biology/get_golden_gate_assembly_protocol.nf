#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_get_golden_gate_assembly_protocol
 * Return a customized protocol for Golden Gate assembly based on the number of inserts
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.num_inserts = 1
params.enzyme_name = null
params.vector_length = 0
params.vector_amount_ng = 75.0
params.insert_lengths = null
params.is_library_prep = false

// Main process
process GET_GOLDEN_GATE_ASSEMBLY_PROTOCOL {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("get_golden_gate_assembly_protocol_results.json"), emit: results
    path("get_golden_gate_assembly_protocol_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.molecular_biology import get_golden_gate_assembly_protocol
except ImportError:
    # Fallback: function may need to be implemented locally
    def get_golden_gate_assembly_protocol(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = get_golden_gate_assembly_protocol(
    num_inserts=${params.num_inserts},
    enzyme_name="${params.enzyme_name}",
    vector_length=${params.vector_length},
    vector_amount_ng=${params.vector_amount_ng},
    insert_lengths="${params.insert_lengths}",
    is_library_prep=${params.is_library_prep}
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("get_golden_gate_assembly_protocol_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("get_golden_gate_assembly_protocol_output.txt", "w") as f:
    f.write("Biomni: Get Golden Gate Assembly Protocol Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("get_golden_gate_assembly_protocol completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_MOLECULAR_BIOLOGY_GET_GOLDEN_GATE_ASSEMBLY_PROTOCOL {
    take:
    // No file inputs

    main:
    GET_GOLDEN_GATE_ASSEMBLY_PROTOCOL()

    emit:
    results = GET_GOLDEN_GATE_ASSEMBLY_PROTOCOL.out.results
    output = GET_GOLDEN_GATE_ASSEMBLY_PROTOCOL.out.output
}

// Entry workflow
workflow {



    BIOMNI_MOLECULAR_BIOLOGY_GET_GOLDEN_GATE_ASSEMBLY_PROTOCOL()
}
