#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: batchelor
// Implements a variety of methods for batch correction of single-cell (RNA sequencing) data. This incl
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/batchelor/inst/doc/correction.R
// Upstream  : knitr, scRNAseq, scater, scran, scuttle
// Downstream: OSCA.advanced, OSCA.intro, OSCA.multisample, OSCA.workflows
//
// Install: BiocManager::install("batchelor")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BATCHELOR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-batchelor"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-batchelor:1.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-batchelor:1.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_batchelor_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_batchelor_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_batchelor_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(batchelor)
    library(NoCorrectParam)
    library(TasicBrainData)
    library(ZeiselBrainData)
    library(jsonlite)

    # --- Multi-Batch PCA and MNN Correction [] ---
    # Key functions: fastMNN, multiBatchPCA
    f_out <- fastMNN(
        A=sce1_norm,
        B=sce2_norm,
        subset.row=chosen_hvgs
    )
    corrected_dims <- SingleCellExperiment::reducedDim(
        f_out,
        "corrected"
    )


    # --- Alternative Batch Correction [] ---
    # Key functions: rescaleBatches, regressBatches
    rescale_out <- rescaleBatches(sce1_norm, sce2_norm)
    regress_out <- regressBatches(sce1_norm, sce2_norm)


    # --- Cluster-based MNN Correction [] ---
    # Key functions: clusterMNN
    clust_out <- clusterMNN(
        sce1_norm,
        sce2_norm,
        subset.row=chosen_hvgs,
        clusters=list(sce1_norm$celltype, sce2_norm$celltype)
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_batchelor_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_batchelor_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_batchelor_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BATCHELOR:", paste0("    batchelor: ", packageVersion("batchelor"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_batchelor_results.csv
    touch ${prefix}_batchelor_output.rds
    echo "BIOC_BATCHELOR:" > versions.yml
    echo "    batchelor: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BATCHELOR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BATCHELOR(ch_input)

    emit:
    results  = BIOC_BATCHELOR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BATCHELOR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BATCHELOR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BATCHELOR.out.versions  // channel: path(versions.yml)
}
