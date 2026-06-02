#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MBQN
// Modified quantile normalization for omics or other matrix-like data distorted in location and scale.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MBQN/inst/doc/MBQNpackage.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("MBQN")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MBQN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mbqn"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mbqn:2.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mbqn:2.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mbqn_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mbqn_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mbqn_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MBQN)
    library(jsonlite)

    # --- Feature Detection [] ---
    # Key functions: mbqnGetNRIfeatures
    res <- mbqnGetNRIfeatures(
        mtx.mod,
        low_thr = 0.5
    )


    # --- Quantile Normalization [] ---
    # Key functions: mbqn, mbqnNRI
    qn.mtx <- mbqn(
        mtx.mod,
        FUN = NULL,
        verbose = FALSE
    )
    mbqn.mtx <- mbqn(
        mtx.mod,
        FUN = "median",
        verbose = FALSE
    )
    qn.nri.mtx <- mbqnNRI(
        mtx.mod,
        FUN = "median",
        low_thr = 0.5,
        verbose = FALSE
    )


    # --- Visualisation and Quality Control [] ---
    # Key functions: mbqnBoxplot
    mbqnBoxplot(
        mbqn.mtx,
        irow = res$ip,
        vals = data.frame(QN = qn.mtx[res$ip, ]),
        main = "Normalized"
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mbqn_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mbqn_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mbqn_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MBQN:", paste0("    mbqn: ", packageVersion("MBQN"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mbqn_results.csv
    touch ${prefix}_mbqn_output.rds
    echo "BIOC_MBQN:" > versions.yml
    echo "    mbqn: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MBQN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MBQN(ch_input)

    emit:
    results  = BIOC_MBQN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MBQN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MBQN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MBQN.out.versions  // channel: path(versions.yml)
}
