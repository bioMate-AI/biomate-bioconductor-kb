#!/usr/bin/env nextflow
/*
 * biomni_genomics_check_ensembl_patterns
 * 
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.gene_index = null

// Main process
process CHECK_ENSEMBL_PATTERNS {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("check_ensembl_patterns_results.json"), emit: results
    path("check_ensembl_patterns_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.genomics import check_ensembl_patterns

# Run the tool
try:
    result = check_ensembl_patterns(
    gene_index="${params.gene_index}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("check_ensembl_patterns_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("check_ensembl_patterns_output.txt", "w") as f:
    f.write("Biomni: Check Ensembl Patterns Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("check_ensembl_patterns completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_GENOMICS_CHECK_ENSEMBL_PATTERNS {
    take:
    // No file inputs

    main:
    CHECK_ENSEMBL_PATTERNS()

    emit:
    results = CHECK_ENSEMBL_PATTERNS.out.results
    output = CHECK_ENSEMBL_PATTERNS.out.output
}

// Entry workflow
workflow {
    if (!params.gene_index) {
        error "Please provide --gene_index parameter"
    }


    BIOMNI_GENOMICS_CHECK_ENSEMBL_PATTERNS()
}
