#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: tigre
// The tigre package implements our methodology of Gaussian process differential equation models for an
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/tigre/inst/doc/tigre.R
// Upstream  : annotate
// Downstream: none
//
// Install: BiocManager::install("tigre")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TIGRE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-tigre"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-tigre:1.60.0--r44_0' :
        'quay.io/biocontainers/bioconductor-tigre:1.60.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_tigre_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_tigre_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_tigre_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(tigre)
    library(GPPlot)
    library(GPRankTargets)
    library(jsonlite)

    # --- GP Model Fitting [] ---
    # Key functions: experimentalAllModels
    gp_models <- experimentalAllModels(
        dataset,
        distrib = "normal",
        clonelog = TRUE
    )


    # --- Target Ranking and Scoring [] ---
    # Key functions: rankResults
    ranked_results <- rankResults(
        gp_models,
        bootstrap = FALSE
    )
    top_targets <- ranked_results[1:10, ]


    # --- Visualization of GP Fits [] ---
    # Key functions: plotGP
    target_gene <- rownames(top_targets)[1]
    plotGP(
        gp_models,
        target_gene,
        col = "red",
        main = paste("GP Fit for Target:", target_gene)
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_tigre_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_tigre_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_tigre_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TIGRE:", paste0("    tigre: ", packageVersion("tigre"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tigre_results.csv
    touch ${prefix}_tigre_output.rds
    echo "BIOC_TIGRE:" > versions.yml
    echo "    tigre: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TIGRE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TIGRE(ch_input)

    emit:
    results  = BIOC_TIGRE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TIGRE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TIGRE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TIGRE.out.versions  // channel: path(versions.yml)
}
