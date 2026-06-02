#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: idr2d
// A tool to measure reproducibility between genomic experiments that produce two-dimensional peaks (in
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/idr2d/inst/doc/idr1d.R
// Upstream  : DT
// Downstream: none
//
// Install: BiocManager::install("idr2d")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_IDR2D {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-idr2d"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-idr2d:1.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-idr2d:1.20.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_idr2d_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_idr2d_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_idr2d_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(idr2d)
    library(jsonlite)

    # --- Withtags [] ---
    # Key functions: withTags, thead, tr, th, datatable
    ---------------------------------------------------------------------
    library(DT)
    # --- Datatable [] ---
    # Key functions: datatable, formatRound
    ---------------------------------------------------------------------
    datatable(rep2_df[seq_len(min(nrow(rep2_df), 1000)), ], container = header,
              rownames = FALSE, options = list(searching = FALSE)) %>%
      formatRound("value", 3)
    # --- Withtags [] ---
    # Key functions: withTags, thead, tr, th, select, datatable
    ---------------------------------------------------------------------
    chr <- start <- end <- rank <- rep_rank <- value <- rep_value <- idr <- NULL

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_idr2d_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_idr2d_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_idr2d_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_IDR2D:", paste0("    idr2d: ", packageVersion("idr2d"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_idr2d_results.csv
    touch ${prefix}_idr2d_output.rds
    echo "BIOC_IDR2D:" > versions.yml
    echo "    idr2d: 0.0.0" >> versions.yml
    """
}


workflow BIOC_IDR2D_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_IDR2D(ch_input)

    emit:
    results  = BIOC_IDR2D.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_IDR2D.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_IDR2D.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_IDR2D.out.versions  // channel: path(versions.yml)
}
