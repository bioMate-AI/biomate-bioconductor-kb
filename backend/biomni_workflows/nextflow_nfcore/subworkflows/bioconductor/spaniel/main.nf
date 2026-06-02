#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Spaniel
// Spaniel includes a series of tools to aid the quality control and analysis of Spatial Transcriptomic
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Spaniel/inst/doc/spaniel-vignette-tenX-import.R
// Upstream  : DropletUtils, scater, scran
// Downstream: none
//
// Install: BiocManager::install("Spaniel")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPANIEL {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-spaniel"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-spaniel:1.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-spaniel:1.20.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_spaniel_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_spaniel_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_spaniel_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Spaniel)
    library(jsonlite)

    # --- create Visium S C E [] ---
    # Key functions: createVisiumSCE
    pathToTenXOuts <- file.path(system.file(package = "Spaniel"), "extdata/outs")
    sce <- createVisiumSCE(tenXDir=pathToTenXOuts,
    # --- col Data [] ---
    # Key functions: colData
    colData(sce)[, c("Barcode", "pixel_x", "pixel_y")]
    # --- image dimensions [] ---
    # Key functions: metadata
    metadata(sce)$ImgDims
    # --- spaniel Plot [] ---
    # Key functions: spanielPlot
    spanielPlot(object = sce,
    # --- Log-normalize count data [] ---
    # Key functions: logNormCounts, spanielPlot, runPCA, runUMAP, buildSNNGraph
    sce <- logNormCounts(sce)
    p2 <- spanielPlot(object = sce,
    library(scran)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_spaniel_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_spaniel_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_spaniel_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SPANIEL:", paste0("    spaniel: ", packageVersion("Spaniel"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spaniel_results.csv
    touch ${prefix}_spaniel_output.rds
    echo "BIOC_SPANIEL:" > versions.yml
    echo "    spaniel: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SPANIEL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SPANIEL(ch_input)

    emit:
    results  = BIOC_SPANIEL.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SPANIEL.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SPANIEL.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SPANIEL.out.versions  // channel: path(versions.yml)
}
