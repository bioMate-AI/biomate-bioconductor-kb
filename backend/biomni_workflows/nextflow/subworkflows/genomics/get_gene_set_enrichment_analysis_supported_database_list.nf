#!/usr/bin/env nextflow
/*
 * biomni_genomics_get_gene_set_enrichment_analysis_supported_database_list
 * 
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'

// Main process
process GET_GENE_SET_ENRICHMENT_ANALYSIS_SUPPORTED_DATABASE_LIST {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("get_gene_set_enrichment_analysis_supported_database_list_results.json"), emit: results
    path("get_gene_set_enrichment_analysis_supported_database_list_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.genomics import get_gene_set_enrichment_analysis_supported_database_list

# Run the tool
try:
    result = get_gene_set_enrichment_analysis_supported_database_list(

    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("get_gene_set_enrichment_analysis_supported_database_list_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("get_gene_set_enrichment_analysis_supported_database_list_output.txt", "w") as f:
    f.write("Biomni: Get Gene Set Enrichment Analysis Supported Database List Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("get_gene_set_enrichment_analysis_supported_database_list completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_GENOMICS_GET_GENE_SET_ENRICHMENT_ANALYSIS_SUPPORTED_DATABASE_LIST {
    take:
    // No file inputs

    main:
    GET_GENE_SET_ENRICHMENT_ANALYSIS_SUPPORTED_DATABASE_LIST()

    emit:
    results = GET_GENE_SET_ENRICHMENT_ANALYSIS_SUPPORTED_DATABASE_LIST.out.results
    output = GET_GENE_SET_ENRICHMENT_ANALYSIS_SUPPORTED_DATABASE_LIST.out.output
}

// Entry workflow
workflow {



    BIOMNI_GENOMICS_GET_GENE_SET_ENRICHMENT_ANALYSIS_SUPPORTED_DATABASE_LIST()
}
