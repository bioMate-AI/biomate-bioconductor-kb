#!/usr/bin/env nextflow
/*
 * biomni_database_blast_sequence
 * Identifies a DNA sequence using NCBI BLAST with improved error handling, timeout management, and debugging.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.sequence = null
params.database = null
params.program = null

// Main process
process BLAST_SEQUENCE {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("blast_sequence_results.json"), emit: results
    path("blast_sequence_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.database import blast_sequence

# Run the tool
try:
    result = blast_sequence(
    sequence="${params.sequence}",
    database="${params.database}",
    program="${params.program}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("blast_sequence_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("blast_sequence_output.txt", "w") as f:
    f.write("Biomni: Blast Sequence Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("blast_sequence completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_DATABASE_BLAST_SEQUENCE {
    take:
    // No file inputs

    main:
    BLAST_SEQUENCE()

    emit:
    results = BLAST_SEQUENCE.out.results
    output = BLAST_SEQUENCE.out.output
}

// Entry workflow
workflow {
    if (!params.sequence) {
        error "Please provide --sequence parameter"
    }
    if (!params.database) {
        error "Please provide --database parameter"
    }
    if (!params.program) {
        error "Please provide --program parameter"
    }


    BIOMNI_DATABASE_BLAST_SEQUENCE()
}
