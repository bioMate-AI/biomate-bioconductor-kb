#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: retrofit
// RETROFIT is a Bayesian non-negative matrix factorization framework to decompose cell type mixtures i
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/retrofit/inst/doc/ColonVignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("retrofit")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RETROFIT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-retrofit"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-retrofit:1.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-retrofit:1.6.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_retrofit_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_retrofit_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_retrofit_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(retrofit)
    library(jsonlite)

    # --- Correlation Annotation [] ---
    # Key functions: annotateWithCorrelations
    sc_ref <- vignetteColonData$sc_ref
    K <- ncol(sc_ref)
    annot_corr <- retrofit::annotateWithCorrelations(
        sc_ref,
        K = K,
        W = W,
        H = H
    )
    H_sc <- annot_corr$h
    W_sc <- annot_corr$w


    # --- Marker Annotation [] ---
    # Key functions: annotateWithMarkers
    marker_ref <- vignetteColonData$marker_ref
    K_mark <- length(marker_ref)
    annot_mark <- retrofit::annotateWithMarkers(
        marker_ref,
        K = K_mark,
        W = W,
        H = H
    )
    H_mark <- annot_mark$h
    W_mark <- annot_mark$w

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_retrofit_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_retrofit_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_retrofit_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RETROFIT:", paste0("    retrofit: ", packageVersion("retrofit"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_retrofit_results.csv
    touch ${prefix}_retrofit_output.rds
    echo "BIOC_RETROFIT:" > versions.yml
    echo "    retrofit: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RETROFIT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RETROFIT(ch_input)

    emit:
    results  = BIOC_RETROFIT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RETROFIT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RETROFIT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RETROFIT.out.versions  // channel: path(versions.yml)
}
