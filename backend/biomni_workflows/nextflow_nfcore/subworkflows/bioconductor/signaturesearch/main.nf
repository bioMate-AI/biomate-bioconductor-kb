#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: signatureSearch
// This package implements algorithms and data structures for performing gene expression signature (GES
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/signatureSearch/inst/doc/signatureSearch.R
// Upstream  : BiocParallel, DT, ExperimentHub, HDF5Array, SummarizedExperiment
// Downstream: DFD
//
// Install: BiocManager::install("signatureSearch")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SIGNATURESEARCH {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-signaturesearch"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-signaturesearch:1.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-signaturesearch:1.20.0--r44_0'}"

    input:
    tuple val(meta), path(summarizedexperiment)

    output:
    tuple val(meta), path("${meta.id}_signaturesearch_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_signaturesearch_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_signaturesearch_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ExperimentHub)
    library(SummarizedExperiment)
    library(jsonlite)

    # --- Data import and loading [] ---
    # Key functions: ExperimentHub, h5ls, SummarizedExperiment, drop, sample
    db_path <- system.file("extdata", "sample_db.h5", package = "signatureSearch")
    library(SummarizedExperiment); library(HDF5Array)
    sample_db <- SummarizedExperiment(HDF5Array(db_path, name="assay"))
    # --- QSig analysis [] ---
    # Key functions: qSig, gess_cmap, result, gess_lincs, gess_gcmap, gess_fisher, gess_cor, gess_res_vis
    query_mat_sub <- as.matrix(query_mat[c(upset, downset),])
    qsig_spsub <- qSig(query = query_mat_sub, gess_method = "Cor", refdb = db_path)
    spsub <- gess_cor(qSig=qsig_spsub, method="spearman", workers=1, addAnnotations = TRUE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_signaturesearch_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_signaturesearch_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_signaturesearch_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SIGNATURESEARCH:", paste0("    signaturesearch: ", packageVersion("signatureSearch"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_signaturesearch_results.csv
    touch ${prefix}_signaturesearch_output.rds
    echo "BIOC_SIGNATURESEARCH:" > versions.yml
    echo "    signaturesearch: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SIGNATURESEARCH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(summarizedexperiment) ]

    main:
    BIOC_SIGNATURESEARCH(ch_input)

    emit:
    results  = BIOC_SIGNATURESEARCH.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SIGNATURESEARCH.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SIGNATURESEARCH.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SIGNATURESEARCH.out.versions  // channel: path(versions.yml)
}
