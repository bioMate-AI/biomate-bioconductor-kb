#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: metagenomeSeq — longitudinal_time_series
// Identify significant time intervals of differential abundance for specific features across two groups in longitudinal studies.
// Input: mouseData
// Container: quay.io/biocontainers/bioconductor-metagenomeseq:1.52.0--r45hdfd78af_0
// Requires: gss, metagenomeSeq
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load longitudinal MRexperiment data
//  * 2. [Core Analysis] Run fitTimeSeries using Smoothing Splines ANOVA (SS-ANOVA) with permutations
//  * 3. [Core Analysis] Extract significant time intervals
//  * 4. [Visualization & Output] Plot the time-series fits using plotClassTimeSeries and plotTimeSeries

nextflow.enable.dsl = 2

process BIOC_METAGENOMESEQ_LONGITUDINAL_TIME_SERIES {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # 1. Load required libraries
    library(metagenomeSeq)
    library(gss)
    
    # Load longitudinal MRexperiment data from the user-provided file
    if (file.exists("mouseData")) {
      mouseData <- readRDS("mouseData")
    } else if (file.exists("mouseData.rds")) {
      mouseData <- readRDS("mouseData.rds")
    } else {
      stop("Error: 'mouseData' file not found in the working directory.")
    }
    
    # 2. Run fitTimeSeries using Smoothing Splines ANOVA (SS-ANOVA) with permutations
    res = fitTimeSeries(obj = mouseData, lvl = "class", feature = "Actinobacteria",
        class = "status", id = "mouseID", time = "relativeTime", B = 10)
    
    # 3. Extract significant time intervals and print structure
    intervals <- res\$timeIntervals
    print(intervals)
    str(res)
    
    # Save the meaningful results to files
    # Save the fit object
    saveRDS(res, file = "time_series_fit.rds")
    
    # Save the significant time intervals table
    if (!is.null(intervals)) {
      write.csv(intervals, file = "significant_time_intervals.csv", row.names = FALSE)
    } else {
      # Create an empty placeholder file if no intervals are found
      write.csv(data.frame(Message = "No significant intervals found"), 
                file = "significant_time_intervals.csv", row.names = FALSE)
    }
    
    # 4. Plot the time-series fits using plotClassTimeSeries and plotTimeSeries
    pdf("time_series_plots.pdf", width = 8, height = 10)
    par(mfrow = c(2, 1))
    plotClassTimeSeries(res, pch = 21, bg = res\$data\$class, ylim = c(0, 8))
    plotTimeSeries(res)
    dev.off()

    writeLines(c(
        '"BIOC_METAGENOMESEQ_LONGITUDINAL_TIME_SERIES":',
        paste0('    metagenomeSeq: ', as.character(packageVersion('metagenomeSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_longitudinal_time_series.csv versions.yml
    """
}

workflow BIOC_METAGENOMESEQ_LONGITUDINAL_TIME_SERIES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ mouseData ] ]

    main:
    BIOC_METAGENOMESEQ_LONGITUDINAL_TIME_SERIES(ch_input)

    emit:
    tables   = BIOC_METAGENOMESEQ_LONGITUDINAL_TIME_SERIES.out.tables
    plots    = BIOC_METAGENOMESEQ_LONGITUDINAL_TIME_SERIES.out.plots
    objects  = BIOC_METAGENOMESEQ_LONGITUDINAL_TIME_SERIES.out.objects
    versions = BIOC_METAGENOMESEQ_LONGITUDINAL_TIME_SERIES.out.versions
}
