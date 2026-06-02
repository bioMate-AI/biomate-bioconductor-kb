#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RIVER
// An implementation of a probabilistic modeling framework that jointly analyzes personal genome and tr
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RIVER/inst/doc/RIVER.R
// Upstream  : devtools
// Downstream: none
//
// Install: BiocManager::install("RIVER")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RIVER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-river"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-river:1.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-river:1.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_river_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_river_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_river_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(RIVER)
    library(jsonlite)

    # --- Model Evaluation [] ---
    # Key functions: evaRIVER
    evaROC <- evaRIVER(
        dataInput,
        pseudoc = 50,
        theta_init = matrix(c(.99, .01, .3, .7), nrow=2),
        costs = c(100, 10, 1, .1, .01, 1e-3, 1e-4),
        verbose = FALSE
    )


    # --- Posterior Probability Estimation and Visualization [] ---
    # Key functions: appRIVER, plotPosteriors
    postprobs <- appRIVER(
        dataInput,
        pseudoc = 50,
        theta_init = matrix(c(.99, .01, .3, .7), nrow=2),
        costs = c(100, 10, 1, .1, .01, 1e-3, 1e-4),
        verbose = FALSE
    )
    plotPosteriors(
        postprobs,
        outliers = as.numeric(unlist(dataInput$Outlier)) - 1
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_river_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_river_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_river_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RIVER:", paste0("    river: ", packageVersion("RIVER"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_river_results.csv
    touch ${prefix}_river_output.rds
    echo "BIOC_RIVER:" > versions.yml
    echo "    river: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RIVER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RIVER(ch_input)

    emit:
    results  = BIOC_RIVER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RIVER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RIVER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RIVER.out.versions  // channel: path(versions.yml)
}
