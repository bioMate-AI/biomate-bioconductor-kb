#!/usr/bin/env nextflow
/*
 * biomni_lab_automation_pick_first
 * 
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.keywords = null

// Main process
process PICK_FIRST {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("pick_first_results.json"), emit: results
    path("pick_first_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.lab_automation import pick_first

# Run the tool
try:
    result = pick_first(
    keywords="${params.keywords}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("pick_first_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("pick_first_output.txt", "w") as f:
    f.write("Biomni: Pick First Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("pick_first completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_LAB_AUTOMATION_PICK_FIRST {
    take:
    // No file inputs

    main:
    PICK_FIRST()

    emit:
    results = PICK_FIRST.out.results
    output = PICK_FIRST.out.output
}

// Entry workflow
workflow {
    if (!params.keywords) {
        error "Please provide --keywords parameter"
    }


    BIOMNI_LAB_AUTOMATION_PICK_FIRST()
}
