#!/usr/bin/env nextflow
/*
 * biomni_genomics_gene_set_enrichment_analysis
 * Perform enrichment analysis for a list of genes, with optional background gene set and plotting functionality.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.genes = null
params.top_k = 10
params.database = 'ontology'
params.background_list = null
params.plot = false

// Main process
process GENE_SET_ENRICHMENT_ANALYSIS {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("gene_set_enrichment_analysis_results.json"), emit: results
    path("gene_set_enrichment_analysis_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.genomics import gene_set_enrichment_analysis

# Run the tool
try:
    result = gene_set_enrichment_analysis(
    genes="${params.genes}",
    top_k=${params.top_k},
    database="${params.database}",
    background_list="${params.background_list}",
    plot=${params.plot ? "True" : "False"}
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("gene_set_enrichment_analysis_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("gene_set_enrichment_analysis_output.txt", "w") as f:
    f.write("Biomni: Gene Set Enrichment Analysis Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("gene_set_enrichment_analysis completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_GENOMICS_GENE_SET_ENRICHMENT_ANALYSIS {
    take:
    // No file inputs

    main:
    GENE_SET_ENRICHMENT_ANALYSIS()

    emit:
    results = GENE_SET_ENRICHMENT_ANALYSIS.out.results
    output = GENE_SET_ENRICHMENT_ANALYSIS.out.output
}

// Entry workflow
workflow {
    if (!params.genes) {
        error "Please provide --genes parameter"
    }


    BIOMNI_GENOMICS_GENE_SET_ENRICHMENT_ANALYSIS()
}
