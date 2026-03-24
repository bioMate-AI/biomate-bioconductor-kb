#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MOMA
// This package implements the inference of candidate master regulator proteins from multi-omics' data 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MOMA/inst/doc/moma.R
// Upstream  : ggplot2, grid
// Downstream: none
//
// Install: BiocManager::install("MOMA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MOMA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-moma"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-moma:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-moma:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_moma_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_moma_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_moma_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MomaConstructor)
    library(jsonlite)

    # --- assays [] ---
    # Key functions: assays
    MultiAssayExperiment::assays(example.gbm.mae)$viper[1:3, 1:3]
    # --- Moma Constructor [] ---
    # Key functions: MomaConstructor
    momaObj <- MomaConstructor(example.gbm.mae, gbm.pathways)
    # --- make Saturation Plots [] ---
    # Key functions: makeSaturationPlots
    plots <- makeSaturationPlots(momaObj)
    # --- visualize plots [] ---
    # Key functions: ggtitle
    library(ggplot2)
    library(grid)
    grid.draw(plots$oncoprint.plots[[3]])

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_moma_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_moma_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_moma_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MOMA:", paste0("    moma: ", packageVersion("MOMA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_moma_results.csv
    touch ${prefix}_moma_output.rds
    echo "BIOC_MOMA:" > versions.yml
    echo "    moma: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MOMA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MOMA(ch_input)

    emit:
    results  = BIOC_MOMA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MOMA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MOMA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MOMA.out.versions  // channel: path(versions.yml)
}
