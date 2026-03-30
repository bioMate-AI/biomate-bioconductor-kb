#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: UCell
// UCell is a package for evaluating gene signatures in single-cell datasets. UCell signature scores, b
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/UCell/inst/doc/UCell_Seurat.R
// Upstream  : Seurat, SingleCellExperiment, ggplot2, patchwork, reshape2
// Downstream: none
//
// Install: BiocManager::install("UCell")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_UCELL {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ucell"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ucell:2.10.1--r44_0' :
        'quay.io/biocontainers/bioconductor-ucell:2.10.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ucell_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ucell_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ucell_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SmoothKNN)
    library(jsonlite)

    # --- Smoothknn [] ---
    # Key functions: SmoothKNN
    ---------------------------------------------------------------------
    seurat.object <- SmoothKNN(seurat.object,
                               signature.names = names(signatures),
                               reduction="pca")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ucell_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ucell_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ucell_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_UCELL:", paste0("    ucell: ", packageVersion("UCell"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ucell_results.csv
    touch ${prefix}_ucell_output.rds
    echo "BIOC_UCELL:" > versions.yml
    echo "    ucell: 0.0.0" >> versions.yml
    """
}


workflow BIOC_UCELL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_UCELL(ch_input)

    emit:
    results  = BIOC_UCELL.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_UCELL.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_UCELL.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_UCELL.out.versions  // channel: path(versions.yml)
}
