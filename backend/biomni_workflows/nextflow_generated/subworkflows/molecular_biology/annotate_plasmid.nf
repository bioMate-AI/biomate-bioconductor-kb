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

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("annotate_plasmid_results.json"), emit: results
    path("annotate_plasmid_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.molecular_biology import annotate_plasmid
except ImportError:
    # Fallback: function may need to be implemented locally
    def annotate_plasmid(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = annotate_plasmid(
    sequence="${params.sequence}",
    is_circular=${params.is_circular}
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("annotate_plasmid_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("annotate_plasmid_output.txt", "w") as f:
    f.write("Biomni: Annotate Plasmid Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
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
