#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: netresponse
// Algorithms for functional network analysis. Includes an implementation of a variational Dirichlet pr
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/netresponse/inst/doc/NetResponse.R
// Upstream  : ggplot2
// Downstream: none
//
// Install: BiocManager::install("netresponse")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NETRESPONSE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-netresponse"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-netresponse:1.66.0--r44_0' :
        'quay.io/biocontainers/bioconductor-netresponse:1.66.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_netresponse_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_netresponse_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_netresponse_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(netresponse)
    library(jsonlite)

    # --- plot_responses [] ---
    # Key functions: plot_responses
    library(ggplot2)
    vis <- plot_responses(res, subnet.id, plot_mode = "pca")
    # --- plot_scale [] ---
    # Key functions: plot_scale
    plot_scale(vis$breaks, vis$palette, two.sided = TRUE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_netresponse_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_netresponse_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_netresponse_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_NETRESPONSE:", paste0("    netresponse: ", packageVersion("netresponse"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_netresponse_results.csv
    touch ${prefix}_netresponse_output.rds
    echo "BIOC_NETRESPONSE:" > versions.yml
    echo "    netresponse: 0.0.0" >> versions.yml
    """
}


workflow BIOC_NETRESPONSE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_NETRESPONSE(ch_input)

    emit:
    results  = BIOC_NETRESPONSE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_NETRESPONSE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_NETRESPONSE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_NETRESPONSE.out.versions  // channel: path(versions.yml)
}
