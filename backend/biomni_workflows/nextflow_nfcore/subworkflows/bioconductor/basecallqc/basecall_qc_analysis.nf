#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: basecallQC — basecall_qc_analysis
// Parse bcl2fastq output metrics, generate summary tables, create QC plots, and compile an HTML report.
// Input: runParameters.xml, config.ini, SampleSheet.csv, ConversionStats.xml, DemultiplexingStats.xml
// Container: quay.io/biocontainers/bioconductor-basecallqc:1.34.0--r45hdfd78af_0
// R packages: basecallQC
// Bioconductor: 3.20 | R: 4.4
// Requires: basecallQC, htmlwidgets
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Initialize run parameters with output directory using BCL2FastQparams()
//  * 2. [Core Analysis] Run the main pipeline using basecallQC()
//  * 3. [Core Analysis] Extract basecalling metrics using baseCallMetrics() and demultiplexing metrics using demultiplexMetrics()
//  * 4. [Visualization & Output] Generate summary tables using summaryConvStatsTable() and summaryDemuxTable()
//  * 5. [Visualization & Output] Create QC plots using passFilterBar(), passFilterTilePlot(), and demuxBarplot()
//  * 6. [Visualization & Output] Compile an HTML report using reportBCL()

nextflow.enable.dsl = 2

process BIOC_BASECALLQC_BASECALL_QC_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("basecallQC")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required library
    library(basecallQC)
    
    # Define input file paths in the working directory
    runXML <- "runParameters.xml"
    config <- "config.ini"
    sampleSheet <- "SampleSheet.csv"
    convStatsInput <- "ConversionStats.xml"
    demuxStatsInput <- "DemultiplexingStats.xml"
    
    # Validate that all required input files exist
    required_files <- c(runXML, config, sampleSheet, convStatsInput, demuxStatsInput)
    for (f in required_files) {
      if (!file.exists(f)) {
        stop(paste("Required input file missing in working directory:", f))
      }
    }
    
    # Set up the output directory structure expected by basecallQC
    # basecallQC expects ConversionStats.xml and DemultiplexingStats.xml to be inside a 'Stats' folder
    outDir <- "out_dir"
    statsDir <- file.path(outDir, "Stats")
    dir.create(statsDir, recursive = TRUE, showWarnings = FALSE)
    
    # Copy the XML metrics files to the expected Stats directory
    file.copy(convStatsInput, file.path(statsDir, "ConversionStats.xml"), overwrite = TRUE)
    file.copy(demuxStatsInput, file.path(statsDir, "DemultiplexingStats.xml"), overwrite = TRUE)
    
    # 1. Initialize run parameters with output directory using BCL2FastQparams()
    bcl2fastqparams <- BCL2FastQparams(runXML, config, runDir = getwd(), outDir, verbose = FALSE)
    
    # 2. Run the main pipeline using basecallQC()
    bclQC <- basecallQC(bcl2fastqparams, RunMetaData = NULL, sampleSheet)
    
    # 3. Extract basecalling metrics and demultiplexing metrics
    bclMetrics <- baseCallMetrics(bcl2fastqparams)
    demuxMetrics <- demultiplexMetrics(bcl2fastqparams)
    
    # Save extracted metrics to RDS files
    saveRDS(bclQC, "bclQC_object.rds")
    saveRDS(bclMetrics, "basecall_metrics.rds")
    saveRDS(demuxMetrics, "demultiplex_metrics.rds")
    
    # 4. Generate summary tables using summaryConvStatsTable() and summaryDemuxTable()
    convTable <- summaryConvStatsTable(bclQC, output = "html")
    demuxTable <- summaryDemuxTable(bclQC, output = "html")
    
    # Save the table objects as RDS
    saveRDS(convTable, "summaryConvStatsTable.rds")
    saveRDS(demuxTable, "summaryDemuxTable.rds")
    
    # Try to save tables as HTML files if htmlwidgets is available
    if (requireNamespace("htmlwidgets", quietly = TRUE)) {
      tryCatch({
        htmlwidgets::saveWidget(convTable, "summaryConvStatsTable.html", selfcontained = TRUE)
        htmlwidgets::saveWidget(demuxTable, "summaryDemuxTable.html", selfcontained = TRUE)
      }, error = function(e) {
        warning("Could not write HTML tables using htmlwidgets: ", e\$message)
      })
    }
    
    # 5. Create QC plots using passFilterBar(), passFilterTilePlot(), and demuxBarplot()
    pdf("basecallQC_plots.pdf", width = 8, height = 8)
    
    # Plot 1: Bar plot of yields per sample
    tryCatch({
      print(passFilterBar(bclQC, groupBy = "Sample", metricToPlot = "Yield"))
    }, error = function(e) {
      warning("Failed to generate passFilterBar plot: ", e\$message)
    })
    
    # Plot 2: Tile plot of specified metric across Lanes and Tiles
    tryCatch({
      print(passFilterTilePlot(bclQC, metricToPlot = "Yield"))
    }, error = function(e) {
      warning("Failed to generate passFilterTilePlot: ", e\$message)
    })
    
    # Plot 3: Bar plot of yield from demultiplexing
    tryCatch({
      print(demuxBarplot(bclQC, groupBy = "Sample"))
    }, error = function(e) {
      warning("Failed to generate demuxBarplot: ", e\$message)
    })
    
    dev.off()
    
    # 6. Compile an HTML report using reportBCL()
    tryCatch({
      reportBCL(bclQC)
    }, error = function(e) {
      warning("Failed to compile HTML report using reportBCL: ", e\$message)
    })

    writeLines(c(
        '"BIOC_BASECALLQC_BASECALL_QC_ANALYSIS":',
        paste0('    basecallQC: ', as.character(packageVersion('basecallQC')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_basecall_qc_analysis.csv versions.yml
    """
}

workflow BIOC_BASECALLQC_BASECALL_QC_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ runParameters.xml, config.ini, SampleSheet.csv, ConversionStats.xml, DemultiplexingStats.xml ] ]

    main:
    BIOC_BASECALLQC_BASECALL_QC_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_BASECALLQC_BASECALL_QC_ANALYSIS.out.tables
    plots    = BIOC_BASECALLQC_BASECALL_QC_ANALYSIS.out.plots
    objects  = BIOC_BASECALLQC_BASECALL_QC_ANALYSIS.out.objects
    versions = BIOC_BASECALLQC_BASECALL_QC_ANALYSIS.out.versions
}
