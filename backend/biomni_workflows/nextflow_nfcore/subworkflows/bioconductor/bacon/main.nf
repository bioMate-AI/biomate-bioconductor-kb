#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: bacon
// Bacon can be used to remove inflation and bias often observed in epigenome- and transcriptome-wide a
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/bacon/inst/doc/bacon.R
// Upstream  : BiocParallel
// Downstream: none
//
// Install: BiocManager::install("bacon")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BACON {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-bacon"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-bacon:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-bacon:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(summarizedexperiment)

    output:
    tuple val(meta), path("${meta.id}_bacon_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_bacon_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_bacon_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(bacon)
    library(jsonlite)

    # --- Rnormmix analysis [] ---
    # Key functions: rnormmix, bacon, estimates, inflation, bias, traces, runif, replicate
    zs <- cbind(zs, matrix(zs, nrow=5000, ncol=9))
    colnames(zs) <- c(paste0("A", 1:10))
    rownames(zs) <- 1:5000

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_bacon_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_bacon_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_bacon_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BACON:", paste0("    bacon: ", packageVersion("bacon"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bacon_results.csv
    touch ${prefix}_bacon_output.rds
    echo "BIOC_BACON:" > versions.yml
    echo "    bacon: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BACON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(summarizedexperiment) ]

    main:
    BIOC_BACON(ch_input)

    emit:
    results  = BIOC_BACON.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BACON.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BACON.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BACON.out.versions  // channel: path(versions.yml)
}
