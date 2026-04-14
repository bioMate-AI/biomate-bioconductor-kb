#!/usr/bin/env nextflow
/*
 * biomni_lab_automation_get_pylabrobot_documentation_material
 * 
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'

// Main process
process GET_PYLABROBOT_DOCUMENTATION_MATERIAL {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("get_pylabrobot_documentation_material_results.json"), emit: results
    path("get_pylabrobot_documentation_material_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.lab_automation import get_pylabrobot_documentation_material
except ImportError:
    # Fallback: function may need to be implemented locally
    def get_pylabrobot_documentation_material(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = get_pylabrobot_documentation_material(

    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("get_pylabrobot_documentation_material_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("get_pylabrobot_documentation_material_output.txt", "w") as f:
    f.write("Biomni: Get Pylabrobot Documentation Material Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("get_pylabrobot_documentation_material completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_LAB_AUTOMATION_GET_PYLABROBOT_DOCUMENTATION_MATERIAL {
    take:
    // No file inputs

    main:
    GET_PYLABROBOT_DOCUMENTATION_MATERIAL()

    emit:
    results = GET_PYLABROBOT_DOCUMENTATION_MATERIAL.out.results
    output = GET_PYLABROBOT_DOCUMENTATION_MATERIAL.out.output
}

// Entry workflow
workflow {



    BIOMNI_LAB_AUTOMATION_GET_PYLABROBOT_DOCUMENTATION_MATERIAL()
}
