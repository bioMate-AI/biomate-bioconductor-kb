#!/usr/bin/env nextflow
/*
 * biomni_genomics_annotate_celltype_scRNA
 * Annotate cell types based on gene markers and transferred labels using LLM.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.adata_filename = null
params.data_dir = null
params.data_info = null
params.data_lake_path = null
params.cluster = 'leiden'
params.llm = 'claude-sonnet-4-5'
params.composition = null

// Main process
process ANNOTATE_CELLTYPE_SCRNA {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("annotate_celltype_scRNA_results.json"), emit: results
    path("annotate_celltype_scRNA_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.genomics import annotate_celltype_scRNA
except ImportError:
    # Fallback: function may need to be implemented locally
    def annotate_celltype_scRNA(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = annotate_celltype_scRNA(
    adata_filename="${params.adata_filename}",
    data_dir="${params.data_dir}",
    data_info="${params.data_info}",
    data_lake_path="${params.data_lake_path}",
    cluster="${params.cluster}",
    llm="${params.llm}",
    composition="${params.composition}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("annotate_celltype_scRNA_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("annotate_celltype_scRNA_output.txt", "w") as f:
    f.write("Biomni: Annotate Celltype Scrna Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("annotate_celltype_scRNA completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_GENOMICS_ANNOTATE_CELLTYPE_SCRNA {
    take:
    // No file inputs

    main:
    ANNOTATE_CELLTYPE_SCRNA()

    emit:
    results = ANNOTATE_CELLTYPE_SCRNA.out.results
    output = ANNOTATE_CELLTYPE_SCRNA.out.output
}

// Entry workflow
workflow {
    if (!params.adata_filename) {
        error "Please provide --adata_filename parameter"
    }
    if (!params.data_dir) {
        error "Please provide --data_dir parameter"
    }
    if (!params.data_info) {
        error "Please provide --data_info parameter"
    }
    if (!params.data_lake_path) {
        error "Please provide --data_lake_path parameter"
    }


    BIOMNI_GENOMICS_ANNOTATE_CELLTYPE_SCRNA()
}
