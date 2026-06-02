#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CytoPipelineGUI
// This package is the companion of the `CytoPipeline` package. It provides GUI's (shiny apps) for the 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CytoPipelineGUI/inst/doc/CytoPipelineGUI.R
// Upstream  : CytoPipeline, patchwork
// Downstream: none
//
// Install: BiocManager::install("CytoPipelineGUI")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CYTOPIPELINEGUI {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cytopipelinegui"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cytopipelinegui:1.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cytopipelinegui:1.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cytopipelinegui_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cytopipelinegui_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cytopipelinegui_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CytoPipelineGUI)
    library(CytoPipeline)
    library(CytoPipelineCheckApp)
    library(ScaleTransformApp)
    library(jsonlite)

    # --- Flow Frame Quality Control [] ---
    # Key functions: plotSelectedFlowFrame
    p1 <- CytoPipelineGUI::plotSelectedFlowFrame(
        experimentName = "OMIP021_PeacoQC",
        whichQueue = "pre-processing",
        sampleFile = 2,
        flowFrameName = "perform_QC_obj",
        path = "workDir",
        xChannelLabel = "Time : NA",
        yChannelLabel = "FSC-A : NA",
        useAllCells = TRUE,
        useFixedLinearRange = FALSE
    )


    # --- Flow Frame Comparison [] ---
    # Key functions: plotDiffFlowFrame
    p_diff <- CytoPipelineGUI::plotDiffFlowFrame(
        path = "workDir",
        experimentNameFrom = "OMIP021_PeacoQC",
        whichQueueFrom = "pre-processing",
        sampleFileFrom = 2,
        flowFrameNameFrom = "perform_QC_obj",
        xChannelLabelFrom = "Time : NA",
        yChannelLabelFrom = "FSC-A : NA",
        experimentNameTo = "OMIP021_flowAI",
        whichQueueTo = "pre-processing",
        sampleFileTo = 2,
        flowFrameNameTo = "perform_QC_obj",
        xChannelLabelTo = "Time : NA",
        yChannelLabelTo = "FSC-A : NA",
        useAllCells = TRUE,
        useFixedLinearRange = FALSE
    )


    # --- Scale Transformation Visualization [] ---
    # Key functions: plotScaleTransformedChannel
    p_trans <- CytoPipelineGUI::plotScaleTransformedChannel(
        fFrame = ff,
        channel = "CD3",
        applyTransform = "data",
        transfoType = "logicle",
        negDecades = 1,
        width = 0.5,
        posDecades = 4
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cytopipelinegui_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cytopipelinegui_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cytopipelinegui_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CYTOPIPELINEGUI:", paste0("    cytopipelinegui: ", packageVersion("CytoPipelineGUI"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cytopipelinegui_results.csv
    touch ${prefix}_cytopipelinegui_output.rds
    echo "BIOC_CYTOPIPELINEGUI:" > versions.yml
    echo "    cytopipelinegui: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CYTOPIPELINEGUI_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CYTOPIPELINEGUI(ch_input)

    emit:
    results  = BIOC_CYTOPIPELINEGUI.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CYTOPIPELINEGUI.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CYTOPIPELINEGUI.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CYTOPIPELINEGUI.out.versions  // channel: path(versions.yml)
}
