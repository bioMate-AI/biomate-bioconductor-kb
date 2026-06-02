#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: dreamlet
// Recent advances in single cell/nucleus transcriptomic technology has enabled collection of cohort-sc
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/dreamlet/inst/doc/cell_covs.R
// Upstream  : ExperimentHub, SingleCellExperiment, lme4, muscat, scater
// Downstream: none
//
// Install: BiocManager::install("dreamlet")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DREAMLET {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-dreamlet"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-dreamlet:1.4.1--r44_0' :
        'quay.io/biocontainers/bioconductor-dreamlet:1.4.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_dreamlet_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_dreamlet_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_dreamlet_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ExperimentHub)
    library(jsonlite)

    # --- Access ExperimentHub data [] ---
    # Key functions: ExperimentHub, perCellQCMetrics, isOutlier
    library(dreamlet)
    library(muscat)
    library(ExperimentHub)
    # --- aggregate To Pseudo Bulk [] ---
    # Key functions: aggregateToPseudoBulk
    sce$id <- paste0(sce$StimStatus, sce$ind)
    # --- metadata [] ---
    # Key functions: metadata
    metadata(pb)$aggr_means
    # --- plot Var Part [] ---
    # Key functions: plotVarPart
    res.proc <- processAssays(pb, form, min.count = 5)
    vp.lst <- fitVarPart(res.proc, form)
    plotVarPart(vp.lst, label.angle = 60)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_dreamlet_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_dreamlet_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_dreamlet_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DREAMLET:", paste0("    dreamlet: ", packageVersion("dreamlet"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dreamlet_results.csv
    touch ${prefix}_dreamlet_output.rds
    echo "BIOC_DREAMLET:" > versions.yml
    echo "    dreamlet: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DREAMLET_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DREAMLET(ch_input)

    emit:
    results  = BIOC_DREAMLET.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DREAMLET.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DREAMLET.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DREAMLET.out.versions  // channel: path(versions.yml)
}
