#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CytoPipeline
// This package provides support for automation and visualization of flow cytometry data analysis pipel
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CytoPipeline/inst/doc/CytoPipeline.R
// Upstream  : ggplot2, reshape2
// Downstream: CytoPipelineGUI
//
// Install: BiocManager::install("CytoPipeline")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CYTOPIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cytopipeline"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cytopipeline:1.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cytopipeline:1.6.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cytopipeline_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cytopipeline_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cytopipeline_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CytoPipeline)
    library(CytoProcessingStep)
    library(jsonlite)

    # --- Pipeline Initialization [Pipeline Setup] ---
    # Key functions: CytoPipeline
    rawDataDir <- system.file("extdata", package = "CytoPipeline")
    sampleFiles <- file.path(
        rawDataDir,
        list.files(rawDataDir, pattern = "Donor")
    )
    pipL_PeacoQC <- CytoPipeline(
        experimentName = "OMIP021_PeacoQC",
        sampleFiles = sampleFiles
    )

    # --- Scale Transformation Queue Setup [Scale Transformation] ---
    # Key functions: addProcessingStep, CytoProcessingStep
    pipL_PeacoQC <- addProcessingStep(
        pipL_PeacoQC,
        whichQueue = "scale transform",
        CytoProcessingStep(
            name = "flowframe_read",
            FUN = "readSampleFiles",
            ARGS = list(truncate_max_range = FALSE, min.limit = NULL)
        )
    )
    pipL_PeacoQC <- addProcessingStep(
        pipL_PeacoQC,
        whichQueue = "scale transform",
        CytoProcessingStep(
            name = "scale_transform_estimate",
            FUN = "estimateScaleTransforms",
            ARGS = list(
                fluoMethod = "estimateLogicle",
                scatterMethod = "linear",
                scatterRefMarker = "BV785 - CD3"
            )
        )
    )

    # --- Pre-processing Queue Setup [Quality Control and Filtering] ---
    # Key functions: addProcessingStep, CytoProcessingStep
    pipL_PeacoQC <- addProcessingStep(
        pipL_PeacoQC,
        whichQueue = "pre-processing",
        CytoProcessingStep(
            name = "perform_QC",
            FUN = "qualityControlPeacoQC",
            ARGS = list(
                preTransform = TRUE,
                min_cells = 150,
                max_bins = 500,
                step = 500,
                MAD = 6
            )
        )
    )
    pipL_PeacoQC <- addProcessingStep(
        pipL_PeacoQC,
        whichQueue = "pre-processing",
        CytoProcessingStep(
            name = "remove_doublets",
            FUN = "removeDoubletsCytoPipeline",
            ARGS = list(
                areaChannels = c("FSC-A", "SSC-A"),
                heightChannels = c("FSC-H", "SSC-H"),
                nmads = c(3, 5)
            )
        )
    )

    # --- Pipeline Execution [Execution] ---
    # Key functions: execute
    workDir <- tempdir()
    execute(pipL_PeacoQC, path = workDir)

    # --- JSON-based Pipeline Configuration [Pipeline Setup] ---
    # Key functions: CytoPipeline
    jsonDir <- system.file("extdata", package = "CytoPipeline")
    sampleFiles <- file.path(
        jsonDir,
        list.files(jsonDir, pattern = "Donor")
    )
    pipL_flowAI <- CytoPipeline(
        file.path(jsonDir, "OMIP021_flowAI_pipeline.json"),
        experimentName = "OMIP021_flowAI",
        sampleFiles = sampleFiles
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cytopipeline_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cytopipeline_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cytopipeline_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CYTOPIPELINE:", paste0("    cytopipeline: ", packageVersion("CytoPipeline"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cytopipeline_results.csv
    touch ${prefix}_cytopipeline_output.rds
    echo "BIOC_CYTOPIPELINE:" > versions.yml
    echo "    cytopipeline: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CYTOPIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CYTOPIPELINE(ch_input)

    emit:
    results  = BIOC_CYTOPIPELINE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CYTOPIPELINE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CYTOPIPELINE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CYTOPIPELINE.out.versions  // channel: path(versions.yml)
}
