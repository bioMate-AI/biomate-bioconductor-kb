#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: HDTD
// Characterization of intra-individual variability using physiologically relevant measurements provide
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/HDTD/inst/doc/HDTD.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("HDTD")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HDTD {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-hdtd"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-hdtd:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-hdtd:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_hdtd_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_hdtd_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_hdtd_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(HDTD)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    library("HDTD")
    data("VEGFmouse")
    dim(VEGFmouse)
    rownames(VEGFmouse)
    # --- Ts [] ---
    # Key functions: ts
    ---------------------------------------------------------------------
    meanmat.ts(VEGFmouse, N = 40, group.sizes = 9)
    # --- Colnames [] ---
    # Key functions: orderdata
    ---------------------------------------------------------------------
    colnames(VEGFmouse)[1:9]
    columnorder <- c(1, 4, 5, 8, 2, 3, 6, 7, 9)
    VEGForder <- orderdata(VEGFmouse, N = 40, order.cols = columnorder)
    colnames(VEGForder)[1:9]
    # --- Ts [] ---
    # Key functions: ts
    ---------------------------------------------------------------------
    meanmat.ts(VEGForder, N = 40, group.sizes = c(4, 1, 1, 1, 1, 1))
    # --- Hat [] ---
    # Key functions: hat
    ---------------------------------------------------------------------
    sample_mean <- meanmat.hat(VEGFmouse, N = 40)
    sample_mean
    # --- Ts [] ---
    # Key functions: ts
    ---------------------------------------------------------------------
    covmat.ts(datamat = VEGFmouse, N = 40, voi = "columns")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_hdtd_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_hdtd_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_hdtd_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_HDTD:", paste0("    hdtd: ", packageVersion("HDTD"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hdtd_results.csv
    touch ${prefix}_hdtd_output.rds
    echo "BIOC_HDTD:" > versions.yml
    echo "    hdtd: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HDTD_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_HDTD(ch_input)

    emit:
    results  = BIOC_HDTD.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HDTD.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HDTD.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HDTD.out.versions  // channel: path(versions.yml)
}
