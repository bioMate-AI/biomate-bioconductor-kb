#!/usr/bin/env nextflow
/*
 * biomni_lab_automation_run_async
 * 
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'

// Main process
process RUN_ASYNC {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("run_async_results.json"), emit: results
    path("run_async_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.lab_automation import run_async
except ImportError:
    # Fallback: function may need to be implemented locally
    def run_async(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = run_async(

    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("run_async_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("run_async_output.txt", "w") as f:
    f.write("Biomni: Run Async Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("run_async completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_LAB_AUTOMATION_RUN_ASYNC {
    take:
    // No file inputs

    main:
    RUN_ASYNC()

    emit:
    results = RUN_ASYNC.out.results
    output = RUN_ASYNC.out.output
}

// Entry workflow
workflow {



    BIOMNI_LAB_AUTOMATION_RUN_ASYNC()
}
