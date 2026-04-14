#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_find_restriction_sites
 * Identifies restriction enzyme sites in a given DNA sequence for specified enzymes.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.dna_sequence = null
params.enzymes = null
params.is_circular = false

// Main process
process FIND_RESTRICTION_SITES {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("find_restriction_sites_results.json"), emit: results
    path("find_restriction_sites_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.molecular_biology import find_restriction_sites

# Run the tool
try:
    result = find_restriction_sites(
    dna_sequence="${params.dna_sequence}",
    enzymes="${params.enzymes}",
    is_circular=${params.is_circular ? "True" : "False"}
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("find_restriction_sites_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("find_restriction_sites_output.txt", "w") as f:
    f.write("Biomni: Find Restriction Sites Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("find_restriction_sites completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_MOLECULAR_BIOLOGY_FIND_RESTRICTION_SITES {
    take:
    // No file inputs

    main:
    FIND_RESTRICTION_SITES()

    emit:
    results = FIND_RESTRICTION_SITES.out.results
    output = FIND_RESTRICTION_SITES.out.output
}

// Entry workflow
workflow {
    if (!params.dna_sequence) {
        error "Please provide --dna_sequence parameter"
    }
    if (!params.enzymes) {
        error "Please provide --enzymes parameter"
    }


    BIOMNI_MOLECULAR_BIOLOGY_FIND_RESTRICTION_SITES()
}
