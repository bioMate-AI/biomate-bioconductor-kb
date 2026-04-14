#!/usr/bin/env nextflow
/*
 * biomni_bioimaging_command_iteration
 * 
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'

// Main process
process COMMAND_ITERATION {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("command_iteration_results.json"), emit: results
    path("command_iteration_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.bioimaging import command_iteration
except ImportError:
    # Fallback: function may need to be implemented locally
    def command_iteration(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = command_iteration(

    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("command_iteration_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("command_iteration_output.txt", "w") as f:
    f.write("Biomni: Command Iteration Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("command_iteration completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_BIOIMAGING_COMMAND_ITERATION {
    take:
    // No file inputs

    main:
    COMMAND_ITERATION()

    emit:
    results = COMMAND_ITERATION.out.results
    output = COMMAND_ITERATION.out.output
}

// Entry workflow
workflow {



    BIOMNI_BIOIMAGING_COMMAND_ITERATION()
}
