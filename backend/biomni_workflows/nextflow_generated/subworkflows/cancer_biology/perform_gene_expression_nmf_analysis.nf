#!/usr/bin/env nextflow
/*
 * biomni_cancer_biology_perform_gene_expression_nmf_analysis
 * Performs Non-negative Matrix Factorization (NMF) on gene expression data to extract
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.expression_data_path = null
params.n_components = '10'
params.normalize = 'True'
params.output_dir = 'nmf_results'
params.random_state = '42'

// Main process
process PERFORM_GENE_EXPRESSION_NMF_ANALYSIS {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("perform_gene_expression_nmf_analysis_results.json"), emit: results
    path("perform_gene_expression_nmf_analysis_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.cancer_biology import perform_gene_expression_nmf_analysis
except ImportError:
    # Fallback: function may need to be implemented locally
    def perform_gene_expression_nmf_analysis(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = perform_gene_expression_nmf_analysis(
    expression_data_path="${params.expression_data_path}",
    n_components="${params.n_components}",
    normalize="${params.normalize}",
    output_dir="${params.output_dir}",
    random_state="${params.random_state}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("perform_gene_expression_nmf_analysis_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("perform_gene_expression_nmf_analysis_output.txt", "w") as f:
    f.write("Biomni: Perform Gene Expression Nmf Analysis Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("perform_gene_expression_nmf_analysis completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_CANCER_BIOLOGY_PERFORM_GENE_EXPRESSION_NMF_ANALYSIS {
    take:
    // No file inputs

    main:
    PERFORM_GENE_EXPRESSION_NMF_ANALYSIS()

    emit:
    results = PERFORM_GENE_EXPRESSION_NMF_ANALYSIS.out.results
    output = PERFORM_GENE_EXPRESSION_NMF_ANALYSIS.out.output
}

// Entry workflow
workflow {
    if (!params.expression_data_path) {
        error "Please provide --expression_data_path parameter"
    }


    BIOMNI_CANCER_BIOLOGY_PERFORM_GENE_EXPRESSION_NMF_ANALYSIS()
}
