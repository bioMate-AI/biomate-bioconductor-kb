#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_annotate_plasmid
 * Annotate a DNA sequence using pLannotate's command-line interface.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.sequence = null
params.is_circular = false

// Main process
process ANNOTATE_PLASMID {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("annotate_plasmid_results.json"), emit: results
    path("annotate_plasmid_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.molecular_biology import annotate_plasmid

# Run the tool
try:
    result = annotate_plasmid(
    sequence="${params.sequence}",
    is_circular=${params.is_circular ? "True" : "False"}
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("annotate_plasmid_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("annotate_plasmid_output.txt", "w") as f:
    f.write("Biomni: Annotate Plasmid Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("annotate_plasmid completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_MOLECULAR_BIOLOGY_ANNOTATE_PLASMID {
    take:
    // No file inputs

    main:
    ANNOTATE_PLASMID()

    emit:
    results = ANNOTATE_PLASMID.out.results
    output = ANNOTATE_PLASMID.out.output
}

// Entry workflow
workflow {
    if (!params.sequence) {
        error "Please provide --sequence parameter"
    }


    BIOMNI_MOLECULAR_BIOLOGY_ANNOTATE_PLASMID()
}
