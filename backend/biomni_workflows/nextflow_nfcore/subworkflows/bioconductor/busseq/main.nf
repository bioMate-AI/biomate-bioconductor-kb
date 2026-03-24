#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BUSseq
// BUSseq R package fits an interpretable Bayesian hierarchical model---the Batch Effects Correction wi
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BUSseq/inst/doc/BUSseq_user_guide.R
// Upstream  : SingleCellExperiment
// Downstream: none
//
// Install: BiocManager::install("BUSseq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BUSSEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-busseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-busseq:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-busseq:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_busseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_busseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_busseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BUSseq_MCMC)
    library(SingleCellExperiment)
    library(jsonlite)

    # --- Create SingleCellExperiment object [] ---
    # Key functions: assay, unlist, SingleCellExperiment
    library(BUSseq)
    library(SingleCellExperiment)
    CountData <- assay(BUSseqfits_example, "counts")
    # --- Assay data access [] ---
    # Key functions: BUSseq_MCMC, assay, celltypes, location_batch_effects, overdispersions, cell_effect_values, celltype_mean_expression, celltype_effects
    celltype_mean_expression_est <- celltype_mean_expression(BUSseqfits_example)
    head(celltype_mean_expression_est)
    celltype_effects_est <- celltype_effects(BUSseqfits_res)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_busseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_busseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_busseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BUSSEQ:", paste0("    busseq: ", packageVersion("BUSseq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_busseq_results.csv
    touch ${prefix}_busseq_output.rds
    echo "BIOC_BUSSEQ:" > versions.yml
    echo "    busseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BUSSEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BUSSEQ(ch_input)

    emit:
    results  = BIOC_BUSSEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BUSSEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BUSSEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BUSSEQ.out.versions  // channel: path(versions.yml)
}
