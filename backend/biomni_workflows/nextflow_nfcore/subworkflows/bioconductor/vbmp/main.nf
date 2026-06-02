#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: vbmp
// Variational Bayesian Multinomial Probit Regression with Gaussian Process Priors. It estimates class 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/vbmp/inst/doc/vbmp.R
// Upstream  : Biobase
// Downstream: none
//
// Install: BiocManager::install("vbmp")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_VBMP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-vbmp"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-vbmp:1.74.0--r44_0' :
        'quay.io/biocontainers/bioconductor-vbmp:1.74.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_vbmp_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_vbmp_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_vbmp_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(vbmp)
    library(U)
    library(jsonlite)

    # --- Variational Bayesian Multinomial Probit Fitting [] ---
    # Key functions: vbmp
    X_train <- matrix(rnorm(200), nrow = 20, ncol = 10)
    y_train <- sample(1:3, 20, replace = TRUE)
    X_test <- matrix(rnorm(100), nrow = 10, ncol = 10)
    y_test <- sample(1:3, 10, replace = TRUE)
    res <- vbmp(
        X_train, y_train, X_test, y_test,
        theta = theta_init,
        control = control_params
    )


    # --- Model Performance Evaluation [] ---
    # Key functions: predError, predClass
    error_rate <- predError(res)
    predicted_labels <- predClass(res)
    out_summary <- list(
        error = error_rate,
        predictions = predicted_labels
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_vbmp_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_vbmp_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_vbmp_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_VBMP:", paste0("    vbmp: ", packageVersion("vbmp"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_vbmp_results.csv
    touch ${prefix}_vbmp_output.rds
    echo "BIOC_VBMP:" > versions.yml
    echo "    vbmp: 0.0.0" >> versions.yml
    """
}


workflow BIOC_VBMP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_VBMP(ch_input)

    emit:
    results  = BIOC_VBMP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_VBMP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_VBMP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_VBMP.out.versions  // channel: path(versions.yml)
}
