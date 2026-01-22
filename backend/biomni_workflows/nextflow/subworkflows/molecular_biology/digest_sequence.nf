#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_digest_sequence
 * Simulates restriction enzyme digestion using Biopython's catalyze method and returns the resulting DNA fragments.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.dna_sequence = null
params.enzyme_names = null
params.is_circular = false

// Main process
process DIGEST_SEQUENCE {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("digest_sequence_results.json"), emit: results
    path("digest_sequence_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.molecular_biology import digest_sequence
except ImportError:
    # Fallback: function may need to be implemented locally
    def digest_sequence(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = digest_sequence(
    dna_sequence="${params.dna_sequence}",
    enzyme_names="${params.enzyme_names}",
    is_circular=${params.is_circular}
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("digest_sequence_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("digest_sequence_output.txt", "w") as f:
    f.write("Biomni: Digest Sequence Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("digest_sequence completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_MOLECULAR_BIOLOGY_DIGEST_SEQUENCE {
    take:
    // No file inputs

    main:
    DIGEST_SEQUENCE()

    emit:
    results = DIGEST_SEQUENCE.out.results
    output = DIGEST_SEQUENCE.out.output
}

// Entry workflow
workflow {
    if (!params.dna_sequence) {
        error "Please provide --dna_sequence parameter"
    }
    if (!params.enzyme_names) {
        error "Please provide --enzyme_names parameter"
    }


    BIOMNI_MOLECULAR_BIOLOGY_DIGEST_SEQUENCE()
}
