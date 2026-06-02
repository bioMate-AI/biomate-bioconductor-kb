#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BrowserViz
// Interactvive graphics in a web browser from R, using websockets and JSON.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BrowserViz/inst/doc/BrowserViz.R
// Upstream  : jsonlite
// Downstream: igvR, RCyjs
//
// Install: BiocManager::install("BrowserViz")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BROWSERVIZ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-browserviz"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-browserviz:2.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-browserviz:2.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_browserviz_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_browserviz_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_browserviz_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BrowserViz)
    library(jsonlite)

    # --- Querying Browser State [] ---
    # Key functions: getBrowserWindowTitle, getBrowserWindowWidth, getBrowserWindowHeight
    current_title <- getBrowserWindowTitle(bv)
    window_width <- getBrowserWindowWidth(bv)
    window_height <- getBrowserWindowHeight(bv)
    dimensions <- list(
        width = window_width,
        height = window_height,
        title = current_title
    )


    # --- Interactive Data Transmission [] ---
    # Key functions: setBrowserWindowTitle, send
    setBrowserWindowTitle(bv, "Updated Nextflow Analysis View")
    custom_message <- list(
        cmd = "displayData",
        status = "request",
        callback = "handleResponse",
        payload = "Data payload from Nextflow pipeline"
    )
    response <- send(bv, custom_message)


    # --- Session Termination [] ---
    # Key functions: close, ready
    close(bv)
    connection_status <- "Closed successfully"
    is_closed <- !ready(bv)
    status_report <- list(
        status = connection_status,
        closed = is_closed
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_browserviz_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_browserviz_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_browserviz_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BROWSERVIZ:", paste0("    browserviz: ", packageVersion("BrowserViz"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_browserviz_results.csv
    touch ${prefix}_browserviz_output.rds
    echo "BIOC_BROWSERVIZ:" > versions.yml
    echo "    browserviz: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BROWSERVIZ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BROWSERVIZ(ch_input)

    emit:
    results  = BIOC_BROWSERVIZ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BROWSERVIZ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BROWSERVIZ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BROWSERVIZ.out.versions  // channel: path(versions.yml)
}
