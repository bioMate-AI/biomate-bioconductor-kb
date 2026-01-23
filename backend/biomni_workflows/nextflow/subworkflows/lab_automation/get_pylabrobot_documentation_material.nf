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

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("get_pylabrobot_documentation_material_results.json"), emit: results
    path("get_pylabrobot_documentation_material_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.lab_automation import get_pylabrobot_documentation_material

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
NL = chr(10)
with open("get_pylabrobot_documentation_material_output.txt", "w") as f:
    f.write("Biomni: Get Pylabrobot Documentation Material Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
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
