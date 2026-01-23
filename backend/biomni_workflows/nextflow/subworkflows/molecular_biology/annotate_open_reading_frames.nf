#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_annotate_open_reading_frames
 * Find all Open Reading Frames (ORFs) in a DNA sequence using Biopython.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.sequence = null
params.min_length = null
params.search_reverse = 'False'
params.filter_subsets = 'False'

// Main process
process ANNOTATE_OPEN_READING_FRAMES {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("annotate_open_reading_frames_results.json"), emit: results
    path("annotate_open_reading_frames_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.molecular_biology import annotate_open_reading_frames

# Run the tool
try:
    result = annotate_open_reading_frames(
    sequence="${params.sequence}",
    min_length="${params.min_length}",
    search_reverse="${params.search_reverse}",
    filter_subsets="${params.filter_subsets}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("annotate_open_reading_frames_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("annotate_open_reading_frames_output.txt", "w") as f:
    f.write("Biomni: Annotate Open Reading Frames Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("annotate_open_reading_frames completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_MOLECULAR_BIOLOGY_ANNOTATE_OPEN_READING_FRAMES {
    take:
    // No file inputs

    main:
    ANNOTATE_OPEN_READING_FRAMES()

    emit:
    results = ANNOTATE_OPEN_READING_FRAMES.out.results
    output = ANNOTATE_OPEN_READING_FRAMES.out.output
}

// Entry workflow
workflow {
    if (!params.sequence) {
        error "Please provide --sequence parameter"
    }
    if (!params.min_length) {
        error "Please provide --min_length parameter"
    }


    BIOMNI_MOLECULAR_BIOLOGY_ANNOTATE_OPEN_READING_FRAMES()
}
