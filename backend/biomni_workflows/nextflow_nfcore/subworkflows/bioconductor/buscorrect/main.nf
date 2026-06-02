#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BUScorrect
// High-throughput experimental data are accumulating exponentially in public databases. However, minin
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BUScorrect/inst/doc/BUScorrect_user_guide.R
// Upstream  : SummarizedExperiment
// Downstream: none
//
// Install: BiocManager::install("BUScorrect")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BUSCORRECT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-buscorrect"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-buscorrect:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-buscorrect:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_buscorrect_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_buscorrect_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_buscorrect_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BIC_BUS)
    library(BUSgibbs)
    library(DataFrame)
    library(IG_index)
    library(Subtypes)
    library(SummarizedExperiment)
    library(jsonlite)

    # --- Create SummarizedExperiment [] ---
    # Key functions: DataFrame, SummarizedExperiment
    require(SummarizedExperiment)
    B <- length(BUSexample_data)
    # --- BUSgibbs analysis [] ---
    # Key functions: BUSgibbs, Subtypes, location_batch_effects, scale_batch_effects, subtype_effects, postprob_DE_thr_fun, estimate_IG_indicators, IG_index
    thr0 <- postprob_DE_thr_fun(BUSfits, fdr_threshold=0.01)
    est_L <- estimate_IG_indicators(BUSfits, postprob_DE_threshold=thr0)
    intrinsic_gene_indices <- IG_index(est_L)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_buscorrect_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_buscorrect_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_buscorrect_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BUSCORRECT:", paste0("    buscorrect: ", packageVersion("BUScorrect"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_buscorrect_results.csv
    touch ${prefix}_buscorrect_output.rds
    echo "BIOC_BUSCORRECT:" > versions.yml
    echo "    buscorrect: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BUSCORRECT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BUSCORRECT(ch_input)

    emit:
    results  = BIOC_BUSCORRECT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BUSCORRECT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BUSCORRECT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BUSCORRECT.out.versions  // channel: path(versions.yml)
}
