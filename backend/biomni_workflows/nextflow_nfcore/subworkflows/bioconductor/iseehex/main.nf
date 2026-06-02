#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: iSEEhex
// This package provides panels summarising data points in hexagonal bins for `iSEE`. It is part of `iS
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/iSEEhex/inst/doc/iSEEhex.R
// Upstream  : BiocStyle, scRNAseq, scater
// Downstream: iSEEu
//
// Install: BiocManager::install("iSEEhex")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ISEEHEX {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-iseehex"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-iseehex:1.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-iseehex:1.8.0--r44_0'}"

    input:
    tuple val(meta), path(seurat_object)

    output:
    tuple val(meta), path("${meta.id}_iseehex_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_iseehex_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_iseehex_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(iSEEhex)
    library(ReducedDimensionHexPlot)
    library(ReducedDimensionPlot)
    library(ReprocessedAllenData)
    library(jsonlite)

    # --- Standard Plot Configuration [] ---
    # Key functions: ReducedDimensionPlot
    dim_panel <- ReducedDimensionPlot(
        ColorBy = "Feature name",
        ColorByFeatureName = "Cux2",
        PanelWidth = 6L
    )


    # --- Interface Initialization [] ---
    # Key functions: iSEE
    initial_panels <- list(dim_panel, hex_panel)
    app <- iSEE(se = sce, initial = initial_panels)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_iseehex_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_iseehex_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_iseehex_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ISEEHEX:", paste0("    iseehex: ", packageVersion("iSEEhex"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_iseehex_results.csv
    touch ${prefix}_iseehex_output.rds
    echo "BIOC_ISEEHEX:" > versions.yml
    echo "    iseehex: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ISEEHEX_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(seurat_object) ]

    main:
    BIOC_ISEEHEX(ch_input)

    emit:
    results  = BIOC_ISEEHEX.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ISEEHEX.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ISEEHEX.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ISEEHEX.out.versions  // channel: path(versions.yml)
}
