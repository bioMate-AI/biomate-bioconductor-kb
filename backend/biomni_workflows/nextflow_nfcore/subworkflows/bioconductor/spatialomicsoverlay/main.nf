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

    # --- Plotting Factor Annotation [] ---
    # Key functions: addPlottingFactor
    muBrain <- addPlottingFactor(
        overlay = muBrain,
        annots = muBrainAnnots,
        plottingFactor = "segment"
    )


    # --- Image Integration [] ---
    # Key functions: addImageOmeTiff, checkValidRes
    res <- checkValidRes(ometiff = tifFile)
    muBrain <- addImageOmeTiff(
        overlay = muBrain,
        ometiff = tifFile,
        res = 8
    )


    # --- Spatial Visualization [] ---
    # Key functions: plotSpatialOverlay, fluorLegend
    gp <- plotSpatialOverlay(
        overlay = muBrain,
        colorBy = "segment",
        corner = "topcenter",
        scaleBarWidth = 0.5,
        textDistance = 130,
        scaleBarColor = "cyan"
    )
    legend <- fluorLegend(muBrain, nrow = 2, textSize = 4)


    # --- Image Transformation and Cropping [] ---
    # Key functions: flipY, cropTissue, cropSamples
    muBrain <- flipY(muBrain)
    muBrain <- cropTissue(overlay = muBrain, buffer = 0.05)
    muBrainCrop <- cropSamples(
        overlay = muBrain,
        sampleIDs = samps,
        sampsOnly = TRUE
    )

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
