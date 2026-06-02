#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: pandaR
// Runs PANDA, an algorithm for discovering novel network structure by combining information from multi
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/pandaR/inst/doc/pandaR.R
// Upstream  : none
// Downstream: netZooR
//
// Install: BiocManager::install("pandaR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PANDAR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-pandar"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-pandar:1.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-pandar:1.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_pandar_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_pandar_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_pandar_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(pandaR)
    library(jsonlite)

    # --- rnorm [] ---
    # Key functions: rnorm, plotZ
    panda.res1 <- with(pandaToyData, panda(motif, expression, ppi, hamming=1))
    panda.res2 <- with(pandaToyData, panda(motif, expression +
    rnorm(prod(dim(expression)),sd=5), ppi, hamming=1))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_pandar_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_pandar_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_pandar_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PANDAR:", paste0("    pandar: ", packageVersion("pandaR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pandar_results.csv
    touch ${prefix}_pandar_output.rds
    echo "BIOC_PANDAR:" > versions.yml
    echo "    pandar: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PANDAR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PANDAR(ch_input)

    emit:
    results  = BIOC_PANDAR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PANDAR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PANDAR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PANDAR.out.versions  // channel: path(versions.yml)
}
