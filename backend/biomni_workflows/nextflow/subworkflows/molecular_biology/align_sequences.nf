#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_align_sequences
 * Align short sequences (primers) to a longer sequence, allowing for one mismatch.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.long_seq = null
params.short_seqs = null

// Main process
process ALIGN_SEQUENCES {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("align_sequences_results.json"), emit: results
    path("align_sequences_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.molecular_biology import align_sequences

# Run the tool
try:
    result = align_sequences(
    long_seq="${params.long_seq}",
    short_seqs="${params.short_seqs}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("align_sequences_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("align_sequences_output.txt", "w") as f:
    f.write("Biomni: Align Sequences Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("align_sequences completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_MOLECULAR_BIOLOGY_ALIGN_SEQUENCES {
    take:
    // No file inputs

    main:
    ALIGN_SEQUENCES()

    emit:
    results = ALIGN_SEQUENCES.out.results
    output = ALIGN_SEQUENCES.out.output
}

// Entry workflow
workflow {
    if (!params.long_seq) {
        error "Please provide --long_seq parameter"
    }
    if (!params.short_seqs) {
        error "Please provide --short_seqs parameter"
    }


    BIOMNI_MOLECULAR_BIOLOGY_ALIGN_SEQUENCES()
}
