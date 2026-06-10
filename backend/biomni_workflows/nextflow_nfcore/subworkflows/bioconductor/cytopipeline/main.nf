#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cytopipeline — peacoqc_preprocessing_pipeline
// Build, execute, and visualize a flow cytometry preprocessing pipeline using PeacoQC for quality control via step-by-step S4 object construction.
// Input: sampleFiles
// Container: quay.io/biocontainers/bioconductor-cytopipeline:1.10.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CYTOPIPELINE_PEACOQC_PREPROCESSING_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-cytopipeline:1.10.0--r45hdfd78af_0"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("cytopipeline", "ggplot2", "reshape2")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(CytoPipeline)
    library(ggplot2)
    library(reshape2)
    
    # 1. Handle User Input
    # The pipeline expects a vector of paths to raw .fcs files named 'sampleFiles'
    if (!exists("sampleFiles")) {
        sampleFiles <- list.files(path = ".", pattern = "\\.fcs\$", full.names = TRUE)
    }
    
    if (length(sampleFiles) == 0) {
        stop("Error: No .fcs files found in the working directory, and 'sampleFiles' is not defined.")
    }
    
    # Define directories
    workDir <- "./cytopipeline_cache"
    outputDir <- "./pipeline_outputs"
    if (!dir.exists(workDir)) dir.create(workDir, recursive = TRUE)
    if (!dir.exists(outputDir)) dir.create(outputDir, recursive = TRUE)
    
    # 2. Initialize CytoPipeline
    experimentName <- "OMIP021_PeacoQC"
    pipL_PeacoQC <- CytoPipeline(experimentName = experimentName,
                                 sampleFiles = sampleFiles)
    
    # 3. Add Scale Transformation Steps
    pipL_PeacoQC <- addProcessingStep(
        pipL_PeacoQC,
        whichQueue = "scale transform",
        CytoProcessingStep(
            name = "flowframe_read",
            FUN = "readSampleFiles",
            ARGS = list(
                whichSamples = "all",
                truncate_max_range = FALSE,
                min.limit = NULL
            )
        )
    )
    
    pipL_PeacoQC <- addProcessingStep(
        pipL_PeacoQC,
        whichQueue = "scale transform",
        CytoProcessingStep(
            name = "remove_margins",
            FUN = "removeMarginsPeacoQC",
            ARGS = list()
        )
    )
    
    pipL_PeacoQC <- addProcessingStep(
        pipL_PeacoQC,
        whichQueue = "scale transform",
        CytoProcessingStep(
            name = "compensate",
            FUN = "compensateFromMatrix",
            ARGS = list(matrixSource = "fcs")
        )
    )
    
    pipL_PeacoQC <- addProcessingStep(
        pipL_PeacoQC,
        whichQueue = "scale transform",
        CytoProcessingStep(
            name = "flowframe_aggregate",
            FUN = "aggregateAndSample",
            ARGS = list(
                nTotalEvents = 10000,
                seed = 0
            )
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
    
    # 4. Add Pre-processing Steps
    pipL_PeacoQC <- addProcessingStep(
        pipL_PeacoQC,
        whichQueue = "pre-processing",
        CytoProcessingStep(
            name = "flowframe_read",
            FUN = "readSampleFiles",
            ARGS = list(
                truncate_max_range = FALSE,
                min.limit = NULL
            )
        )
    )
    
    pipL_PeacoQC <- addProcessingStep(
        pipL_PeacoQC,
        whichQueue = "pre-processing",
        CytoProcessingStep(
            name = "remove_margins",
            FUN = "removeMarginsPeacoQC",
            ARGS = list()
        )
    )
    
    pipL_PeacoQC <- addProcessingStep(
        pipL_PeacoQC,
        whichQueue = "pre-processing",
        CytoProcessingStep(
            name = "compensate",
            FUN = "compensateFromMatrix",
            ARGS = list(matrixSource = "fcs")
        )
    )
    
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
                MAD = 6,
                IT_limit = 0.55,
                force_IT = 150,
                peak_removal = 0.3333,
                min_nr_bins_peakdetection = 10
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
    
    pipL_PeacoQC <- addProcessingStep(
        pipL_PeacoQC,
        whichQueue = "pre-processing",
        CytoProcessingStep(
            name = "remove_debris",
            FUN = "removeDebrisManualGate",
            ARGS = list(
                FSCChannel = "FSC-A",
                SSCChannel = "SSC-A",
                gateData = c(73615, 110174, 213000, 201000, 126000,
                             47679, 260500, 260500, 113000, 35000)
            )
        )
    )
    
    pipL_PeacoQC <- addProcessingStep(
        pipL_PeacoQC,
        whichQueue = "pre-processing",
        CytoProcessingStep(
            name = "remove_dead_cells",
            FUN = "removeDeadCellsManualGate",
            ARGS = list(
                FSCChannel = "FSC-A",
                LDMarker = "L/D Aqua - Viability",
                gateData = c(0, 0, 250000, 250000,
                             0, 650, 650, 0)
            )
        )
    )
    
    # 5. Execute Pipeline
    message("Executing PeacoQC pipeline...")
    execute(pipL_PeacoQC, path = workDir)
    
    # 6. Visualize and Inspect Intermediate Results
    
    # Plot workflow graphs
    message("Saving workflow graphs...")
    pdf(file.path(outputDir, "workflow_scale_transform.pdf"))
    plotCytoPipelineProcessingQueue(
        pipL_PeacoQC,
        whichQueue = "scale transform",
        path = workDir
    )
    dev.off()
    
    pdf(file.path(outputDir, "workflow_preprocessing.pdf"))
    plotCytoPipelineProcessingQueue(
        pipL_PeacoQC,
        whichQueue = "pre-processing",
        sampleFile = 1,
        path = workDir
    )
    dev.off()
    
    # Get object information and save to CSV
    message("Saving pipeline object information...")
    info_scale <- getCytoPipelineObjectInfos(
        pipL_PeacoQC,
        path = workDir,
        whichQueue = "scale transform"
    )
    write.csv(info_scale, file.path(outputDir, "scale_transform_infos.csv"), row.names = FALSE)
    
    info_preproc <- getCytoPipelineObjectInfos(
        pipL_PeacoQC,
        path = workDir,
        whichQueue = "pre-processing",
        sampleFile = sampleFiles(pipL_PeacoQC)[1]
    )
    write.csv(info_preproc, file.path(outputDir, "preprocessing_infos.csv"), row.names = FALSE)
    
    # Retrieve flow frames and plot events
    message("Retrieving flow frames and generating event plots...")
    ff <- getCytoPipelineFlowFrame(
        pipL_PeacoQC,
        whichQueue = "pre-processing",
        sampleFile = 1,
        objectName = "remove_doublets_obj",
        path = workDir
    )
    
    ff2 <- getCytoPipelineFlowFrame(
        pipL_PeacoQC,
        whichQueue = "pre-processing",
        sampleFile = 1,
        objectName = "remove_debris_obj",
        path = workDir
    )
    
    pdf(file.path(outputDir, "ggplot_events_fsc_a.pdf"))
    print(ggplotEvents(ff, xChannel = "FSC-A"))
    dev.off()
    
    pdf(file.path(outputDir, "ggplot_events_fsc_ssc.pdf"))
    print(ggplotEvents(ff, xChannel = "FSC-A", yChannel = "SSC-A"))
    dev.off()
    
    pdf(file.path(outputDir, "ggplot_filter_events.pdf"))
    print(ggplotFilterEvents(ff, ff2, xChannel = "FSC-A", yChannel = "SSC-A"))
    dev.off()
    
    # Retrieve non-flowFrame object from cache and save as RDS
    message("Retrieving compensated flowSet from cache...")
    obj <- getCytoPipelineObjectFromCache(
        pipL_PeacoQC,
        path = workDir,
        whichQueue = "scale transform",
        objectName = "compensate_obj"
    )
    saveRDS(obj, file.path(outputDir, "compensate_obj.rds"))
    
    # Collect and process retained events statistics
    message("Collecting retained events statistics...")
    ret <- CytoPipeline::collectNbOfRetainedEvents(
        experimentName = "OMIP021_PeacoQC",
        path = workDir
    )
    write.csv(ret, file.path(outputDir, "retained_events_count.csv"))
    
    retainedProp <- as.data.frame(t(apply(
        ret,
        MARGIN = 1,
        FUN = function(line) {
            if (length(line) == 0 || is.na(line[1])) {
                as.numeric(rep(NA, length(line)))
            } else {
                round(line / line[1], 3)
            }
        }
    )))
    retainedProp <- retainedProp[-1]
    write.csv(retainedProp, file.path(outputDir, "retained_proportion.csv"))
    
    stepRemovedProp <- as.data.frame(t(apply(
        ret,
        MARGIN = 1,
        FUN = function(line) {
            if (length(line) == 0) {
                as.numeric(rep(NA, length(line)))
            } else {
                round(1 - line / dplyr::lag(line), 3)
            }
        }
    )))
    stepRemovedProp <- stepRemovedProp[-1]
    write.csv(stepRemovedProp, file.path(outputDir, "step_removed_proportion.csv"))
    
    # Plot retained and removed proportions
    myGGPlot <- function(DF, title) {
        stepNames <- colnames(DF)
        rowNames <- rownames(DF)
        DFLongFmt <- reshape(
            DF,
            direction = "long",
            v.names = "proportion",
            varying = stepNames,
            timevar = "step",
            time = stepNames,
            ids = rowNames
        )
        DFLongFmt\$step <- factor(DFLongFmt\$step, levels = stepNames)
        
        ggplot(data = DFLongFmt, mapping = aes(x = step, y = proportion, text = id)) +
            geom_point(col = "blue") +
            ggtitle(title) +
            theme(axis.text.x = element_text(angle = 90))
    }
    
    pdf(file.path(outputDir, "retained_event_proportion_plot.pdf"))
    print(myGGPlot(DF = retainedProp, title = "Retained event proportion at each step"))
    dev.off()
    
    pdf(file.path(outputDir, "event_proportion_removed_plot.pdf"))
    print(myGGPlot(DF = stepRemovedProp, title = "Event proportion removed by each step"))
    dev.off()
    
    message("Pipeline execution and visualization complete. Outputs saved to: ", outputDir)

    cat <<-END_VERSIONS > versions.yml
    "BIOC_CYTOPIPELINE_PEACOQC_PREPROCESSING_PIPELINE":
        cytopipeline: \$(Rscript -e 'cat(as.character(packageVersion("cytopipeline")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_peacoqc_preprocessing_pipeline.csv versions.yml
    """
}

workflow BIOC_CYTOPIPELINE_PEACOQC_PREPROCESSING_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sampleFiles ] ]

    main:
    BIOC_CYTOPIPELINE_PEACOQC_PREPROCESSING_PIPELINE(ch_input)

    emit:
    tables   = BIOC_CYTOPIPELINE_PEACOQC_PREPROCESSING_PIPELINE.out.tables
    plots    = BIOC_CYTOPIPELINE_PEACOQC_PREPROCESSING_PIPELINE.out.plots
    objects  = BIOC_CYTOPIPELINE_PEACOQC_PREPROCESSING_PIPELINE.out.objects
    versions = BIOC_CYTOPIPELINE_PEACOQC_PREPROCESSING_PIPELINE.out.versions
}
