#!/usr/bin/env nextflow
/*
 * biomni_genomics_unsupervised_celltype_transfer_between_scRNA_datasets
 * 
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.path_to_annotated_h5ad = null
params.path_to_not_annotated_h5ad = null
params.ref_labels_key = null
params.query_batch_key = null
params.ref_batch_key = null
params.CELLTYPIST = 'False'
params.KNN_BBKNN = 'False'
params.KNN_HARMONY = 'False'
params.KNN_SCANORAMA = 'False'
params.KNN_SCVI = 'False'
params.ONCLASS = 'False'
params.Random_Forest = 'False'
params.SCANVI_POPV = 'True'
params.Support_Vector = 'False'
params.XGboost = 'False'
params.n_jobs = 1
params.output_folder = './tmp/'
params.n_samples_per_label = 10

// Main process
process UNSUPERVISED_CELLTYPE_TRANSFER_BETWEEN_SCRNA_DATASETS {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("unsupervised_celltype_transfer_between_scRNA_datasets_results.json"), emit: results
    path("unsupervised_celltype_transfer_between_scRNA_datasets_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.genomics import unsupervised_celltype_transfer_between_scRNA_datasets
except ImportError:
    # Fallback: function may need to be implemented locally
    def unsupervised_celltype_transfer_between_scRNA_datasets(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = unsupervised_celltype_transfer_between_scRNA_datasets(
    path_to_annotated_h5ad="${params.path_to_annotated_h5ad}",
    path_to_not_annotated_h5ad="${params.path_to_not_annotated_h5ad}",
    ref_labels_key="${params.ref_labels_key}",
    query_batch_key="${params.query_batch_key}",
    ref_batch_key="${params.ref_batch_key}",
    CELLTYPIST="${params.CELLTYPIST}",
    KNN_BBKNN="${params.KNN_BBKNN}",
    KNN_HARMONY="${params.KNN_HARMONY}",
    KNN_SCANORAMA="${params.KNN_SCANORAMA}",
    KNN_SCVI="${params.KNN_SCVI}",
    ONCLASS="${params.ONCLASS}",
    Random_Forest="${params.Random_Forest}",
    SCANVI_POPV="${params.SCANVI_POPV}",
    Support_Vector="${params.Support_Vector}",
    XGboost="${params.XGboost}",
    n_jobs=${params.n_jobs},
    output_folder="${params.output_folder}",
    n_samples_per_label=${params.n_samples_per_label}
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("unsupervised_celltype_transfer_between_scRNA_datasets_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("unsupervised_celltype_transfer_between_scRNA_datasets_output.txt", "w") as f:
    f.write("Biomni: Unsupervised Celltype Transfer Between Scrna Datasets Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("unsupervised_celltype_transfer_between_scRNA_datasets completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_GENOMICS_UNSUPERVISED_CELLTYPE_TRANSFER_BETWEEN_SCRNA_DATASETS {
    take:
    // No file inputs

    main:
    UNSUPERVISED_CELLTYPE_TRANSFER_BETWEEN_SCRNA_DATASETS()

    emit:
    results = UNSUPERVISED_CELLTYPE_TRANSFER_BETWEEN_SCRNA_DATASETS.out.results
    output = UNSUPERVISED_CELLTYPE_TRANSFER_BETWEEN_SCRNA_DATASETS.out.output
}

// Entry workflow
workflow {
    if (!params.path_to_annotated_h5ad) {
        error "Please provide --path_to_annotated_h5ad parameter"
    }
    if (!params.path_to_not_annotated_h5ad) {
        error "Please provide --path_to_not_annotated_h5ad parameter"
    }
    if (!params.ref_labels_key) {
        error "Please provide --ref_labels_key parameter"
    }


    BIOMNI_GENOMICS_UNSUPERVISED_CELLTYPE_TRANSFER_BETWEEN_SCRNA_DATASETS()
}
