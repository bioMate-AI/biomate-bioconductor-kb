#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SpatialOmicsOverlay
// Tools for NanoString Technologies GeoMx Technology. Package to easily graph on top of an OME-TIFF im
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SpatialOmicsOverlay/inst/doc/SpatialOmicsOverlay.R
// Upstream  : GeomxTools, cowplot
// Downstream: none
//
// Install: BiocManager::install("SpatialOmicsOverlay")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPATIALOMICSOVERLAY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-spatialomicsoverlay"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-spatialomicsoverlay:1.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-spatialomicsoverlay:1.6.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_spatialomicsoverlay_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_spatialomicsoverlay_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_spatialomicsoverlay_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SpatialOmicsOverlay)
    library(jsonlite)

    # --- download Mouse Brain Image [] ---
    # Key functions: downloadMouseBrainImage
    tifFile <- downloadMouseBrainImage()
    # --- Read in Data [] ---
    # Key functions: readSpatialOverlay

    # --- object accessors [] ---
    # Key functions: slideName
    head(sampNames(muBrain))
    slideName(muBrain)
    head(meta(overlay(muBrain)))
    # --- plot w/o image Sample ID [] ---
    # Key functions: plotSpatialOverlay
    plotSpatialOverlay(overlay = muBrain, hiRes = FALSE, legend = FALSE)
    # --- add plotting factors [] ---
    # Key functions: readLabWorksheet, addPlottingFactor
    muBrainAnnots <- readLabWorksheet(lw = muBrainLW, slideName = "D5761 (3)")
    # --- customizable ggplot [] ---
    # Key functions: plotSpatialOverlay, scale_color_viridis, labs

    # --- check Valid Res [] ---
    # Key functions: checkValidRes, addImageOmeTiff, showImage
    checkValidRes(ometiff = tifFile)
    muBrain <- addImageOmeTiff(overlay = muBrain, ometiff = tifFile, res = res)
    showImage(muBrain)
    # --- plot with image [] ---
    # Key functions: plotSpatialOverlay

    # --- fluorLegend in plotSpatialOverlay [] ---
    # Key functions: plotSpatialOverlay

    # --- fluorLegend function [] ---
    # Key functions: plotSpatialOverlay, fluorLegend, ggdraw, draw_plot
    library(cowplot)
    # --- flip Y [] ---
    # Key functions: flipY, plotSpatialOverlay
    muBrain <- flipY(muBrain)
    plotSpatialOverlay(overlay = muBrain, colorBy = "segment", scaleBar = FALSE)
    plotSpatialOverlay(overlay = flipX(muBrain), colorBy = "segment", scaleBar = FALSE)
    # --- crop Tissue [] ---
    # Key functions: cropTissue, plotSpatialOverlay, scale_fill_viridis
    muBrain <- cropTissue(overlay = muBrain, buffer = 0.05)
    plotSpatialOverlay(overlay = muBrain, colorBy = "ROILabel", legend = FALSE, scaleBar = FALSE)+
    viridis::scale_fill_viridis(option = "C")
    # --- crop Samples [] ---
    # Key functions: cropSamples, plotSpatialOverlay, scale_fill_gradient2
    muBrainAnnots$slide.name == slideName(muBrain)]
    muBrainCrop <- cropSamples(overlay = muBrain, sampleIDs = samps, sampsOnly = TRUE)
    # --- add4 Channel Image [] ---
    # Key functions: add4ChannelImage, fluor, changeImageColoring, changeColoringIntensity, recolor
    chan4 <- add4ChannelImage(overlay = muBrain)
    fluor(chan4)
    chan4 <- changeImageColoring(overlay = chan4, color = "#32a8a4", dye = "FITC")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_spatialomicsoverlay_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_spatialomicsoverlay_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_spatialomicsoverlay_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SPATIALOMICSOVERLAY:", paste0("    spatialomicsoverlay: ", packageVersion("SpatialOmicsOverlay"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spatialomicsoverlay_results.csv
    touch ${prefix}_spatialomicsoverlay_output.rds
    echo "BIOC_SPATIALOMICSOVERLAY:" > versions.yml
    echo "    spatialomicsoverlay: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SPATIALOMICSOVERLAY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SPATIALOMICSOVERLAY(ch_input)

    emit:
    results  = BIOC_SPATIALOMICSOVERLAY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SPATIALOMICSOVERLAY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SPATIALOMICSOVERLAY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SPATIALOMICSOVERLAY.out.versions  // channel: path(versions.yml)
}
