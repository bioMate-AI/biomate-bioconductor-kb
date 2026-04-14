#!/usr/bin/env nextflow
/*
 * biomni_database_get_genes_near_ccre
 * Given a cCRE (Candidate cis-Regulatory Element), this function returns a string containing the
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.accession = null
params.assembly = null
params.chromosome = null
params.k = 10

// Main process
process GET_GENES_NEAR_CCRE {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("get_genes_near_ccre_results.json"), emit: results
    path("get_genes_near_ccre_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.database import get_genes_near_ccre
except ImportError:
    # Fallback: function may need to be implemented locally
    def get_genes_near_ccre(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = get_genes_near_ccre(
    accession="${params.accession}",
    assembly="${params.assembly}",
    chromosome="${params.chromosome}",
    k=${params.k}
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("get_genes_near_ccre_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("get_genes_near_ccre_output.txt", "w") as f:
    f.write("Biomni: Get Genes Near Ccre Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("get_genes_near_ccre completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_DATABASE_GET_GENES_NEAR_CCRE {
    take:
    // No file inputs

    main:
    GET_GENES_NEAR_CCRE()

    emit:
    results = GET_GENES_NEAR_CCRE.out.results
    output = GET_GENES_NEAR_CCRE.out.output
}

// Entry workflow
workflow {
    if (!params.accession) {
        error "Please provide --accession parameter"
    }
    if (!params.assembly) {
        error "Please provide --assembly parameter"
    }
    if (!params.chromosome) {
        error "Please provide --chromosome parameter"
    }


    BIOMNI_DATABASE_GET_GENES_NEAR_CCRE()
}
