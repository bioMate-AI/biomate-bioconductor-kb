#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: cytomapper
// Highly multiplexed imaging acquires the single-cell expression of selected proteins in a spatially-r
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/cytomapper/inst/doc/cytomapper.R
// Upstream  : HDF5Array, cowplot, ggplot2
// Downstream: none
//
// Install: BiocManager::install("cytomapper")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CYTOMAPPER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cytomapper"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cytomapper:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cytomapper:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cytomapper_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cytomapper_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cytomapper_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(cytomapper)
    library(jsonlite)

    # --- Custom ggplot2 visualization [] ---
    # Key functions: ggplot, plotCells, ggdraw, plot_grid
    library(cowplot)
    library(ggplot2)
    g1 <- ggplot(mtcars) + geom_point(aes(cyl, hp))
    # --- Sample metadata inspection [] ---
    # Key functions: plotPixels, plotCells, mcols, channelNames, imageData, loadImages, scaleImages, measureObjects
    path.to.images <- system.file("extdata", package = "cytomapper")
    all_masks <- loadImages(path.to.images, pattern = "_mask.tiff")
    all_stacks <- loadImages(path.to.images, pattern = "_imc.tiff")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cytomapper_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cytomapper_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cytomapper_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CYTOMAPPER:", paste0("    cytomapper: ", packageVersion("cytomapper"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cytomapper_results.csv
    touch ${prefix}_cytomapper_output.rds
    echo "BIOC_CYTOMAPPER:" > versions.yml
    echo "    cytomapper: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CYTOMAPPER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CYTOMAPPER(ch_input)

    emit:
    results  = BIOC_CYTOMAPPER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CYTOMAPPER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CYTOMAPPER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CYTOMAPPER.out.versions  // channel: path(versions.yml)
}
