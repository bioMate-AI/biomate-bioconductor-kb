#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: nempi
// Takes as input an incomplete perturbation profile and differential gene expression in log odds and i
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/nempi/inst/doc/nempi.R
// Upstream  : mnem
// Downstream: none
//
// Install: BiocManager::install("nempi")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NEMPI {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-nempi"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-nempi:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-nempi:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_nempi_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_nempi_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_nempi_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(nempi)
    library(jsonlite)

    # --- Supervised Perturbation Classification [] ---
    # Key functions: classpi
    # Classify unlabelled cells using supervised machine learning methods
    # such as Support Vector Machines, Neural Networks, or Random Forests.
    res_svm <- classpi(data, method = "svm")
    res_nnet <- classpi(data, method = "nnet")
    res_rf <- classpi(data, method = "randomForest")


    # --- Model Performance Evaluation [] ---
    # Key functions: pifit
    # Evaluate the accuracy of the inferred perturbation profiles
    # against a ground truth simulation or known benchmark.
    fit_nempi <- pifit(res_nempi, simmini, data)
    fit_svm <- pifit(res_svm, simmini, data, propagate = FALSE)
    
    # Collect Area Under the Curve (AUC) metrics for comparison
    auc_results <- list(
        nempi = fit_nempi$auc,
        svm = fit_svm$auc
    )


    # --- Visualisation of Inferred Profiles [] ---
    # Key functions: plot
    # Visualise the inferred perturbation matrix and network structure
    # using custom color gradients for the heatmaps and barplots.
    col_grad <- rgb(
        seq(0, 1, length.out = 10),
        seq(1, 0, length.out = 10),
        seq(1, 0, length.out = 10)
    )
    plot(
        res_nempi,
        heatlist = list(col = "RdBu"),
        barlist = list(col = col_grad)
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_nempi_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_nempi_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_nempi_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_NEMPI:", paste0("    nempi: ", packageVersion("nempi"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_nempi_results.csv
    touch ${prefix}_nempi_output.rds
    echo "BIOC_NEMPI:" > versions.yml
    echo "    nempi: 0.0.0" >> versions.yml
    """
}


workflow BIOC_NEMPI_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_NEMPI(ch_input)

    emit:
    results  = BIOC_NEMPI.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_NEMPI.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_NEMPI.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_NEMPI.out.versions  // channel: path(versions.yml)
}
