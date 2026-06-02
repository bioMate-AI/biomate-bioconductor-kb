#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: methyLImp2
// This package allows to estimate missing values in DNA methylation data. methyLImp method is based on
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/methyLImp2/inst/doc/methyLImp2_vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("methyLImp2")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_METHYLIMP2 {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-methylimp2"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-methylimp2:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-methylimp2:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_methylimp2_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_methylimp2_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_methylimp2_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(methyLImp2)
    library(SummarizedExperiment)
    library(jsonlite)

    # --- Methylation Imputation [] ---
    # Key functions: methyLImp2
    beta_SE_imputed <- methyLImp2::methyLImp2(
        input = beta_SE,
        type = "EPIC",
        BPPARAM = BiocParallel::SnowParam(exportglobals = FALSE),
        minibatch_frac = 0.5
    )


    # --- Performance Evaluation [] ---
    # Key functions: evaluatePerformance
    performance <- methyLImp2::evaluatePerformance(
        beta,
        t(SummarizedExperiment::assays(beta_SE_imputed)[[1]]),
        na_positions
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_methylimp2_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_methylimp2_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_methylimp2_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_METHYLIMP2:", paste0("    methylimp2: ", packageVersion("methyLImp2"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_methylimp2_results.csv
    touch ${prefix}_methylimp2_output.rds
    echo "BIOC_METHYLIMP2:" > versions.yml
    echo "    methylimp2: 0.0.0" >> versions.yml
    """
}


workflow BIOC_METHYLIMP2_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_METHYLIMP2(ch_input)

    emit:
    results  = BIOC_METHYLIMP2.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_METHYLIMP2.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_METHYLIMP2.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_METHYLIMP2.out.versions  // channel: path(versions.yml)
}
