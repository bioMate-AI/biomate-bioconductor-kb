#!/usr/bin/env nextflow
/*
 * biomni_glycoengineering_list_glycoengineering_resources
 * Curate and summarize external glycoengineering tools and resources.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'

// Main process
process LIST_GLYCOENGINEERING_RESOURCES {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("list_glycoengineering_resources_results.json"), emit: results
    path("list_glycoengineering_resources_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.glycoengineering import list_glycoengineering_resources

# Run the tool
try:
    result = list_glycoengineering_resources(

    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("list_glycoengineering_resources_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("list_glycoengineering_resources_output.txt", "w") as f:
    f.write("Biomni: List Glycoengineering Resources Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("list_glycoengineering_resources completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_GLYCOENGINEERING_LIST_GLYCOENGINEERING_RESOURCES {
    take:
    // No file inputs

    main:
    LIST_GLYCOENGINEERING_RESOURCES()

    emit:
    results = LIST_GLYCOENGINEERING_RESOURCES.out.results
    output = LIST_GLYCOENGINEERING_RESOURCES.out.output
}

// Entry workflow
workflow {



    BIOMNI_GLYCOENGINEERING_LIST_GLYCOENGINEERING_RESOURCES()
}
