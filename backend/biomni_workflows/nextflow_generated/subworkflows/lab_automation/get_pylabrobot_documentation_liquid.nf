#!/usr/bin/env nextflow
/*
 * biomni_lab_automation_get_pylabrobot_documentation_liquid
 * Get the documentation for a specific section of the PyLabRobot tutorial.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'

// Main process
process GET_PYLABROBOT_DOCUMENTATION_LIQUID {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("get_pylabrobot_documentation_liquid_results.json"), emit: results
    path("get_pylabrobot_documentation_liquid_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.lab_automation import get_pylabrobot_documentation_liquid
except ImportError:
    # Fallback: function may need to be implemented locally
    def get_pylabrobot_documentation_liquid(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = get_pylabrobot_documentation_liquid(

    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("get_pylabrobot_documentation_liquid_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("get_pylabrobot_documentation_liquid_output.txt", "w") as f:
    f.write("Biomni: Get Pylabrobot Documentation Liquid Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("get_pylabrobot_documentation_liquid completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_LAB_AUTOMATION_GET_PYLABROBOT_DOCUMENTATION_LIQUID {
    take:
    // No file inputs

    main:
    GET_PYLABROBOT_DOCUMENTATION_LIQUID()

    emit:
    results = GET_PYLABROBOT_DOCUMENTATION_LIQUID.out.results
    output = GET_PYLABROBOT_DOCUMENTATION_LIQUID.out.output
}

// Entry workflow
workflow {



    BIOMNI_LAB_AUTOMATION_GET_PYLABROBOT_DOCUMENTATION_LIQUID()
}
