#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: basecallqc — bcl2fastq_qc_analysis_and_reporting
// Parse bcl2fastq output metrics, run the basecallQC pipeline, and generate summary tables, plots, and an HTML report.
// Input: runParameters.xml, config.ini, SampleSheet.csv, ConversionStats.xml, DemultiplexingStats.xml
// Container: quay.io/biocontainers/bioconductor-basecallqc:1.34.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BASECALLQC_BCL2FASTQ_QC_ANALYSIS_AND_REPORTING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-basecallqc:1.34.0--r45hdfd78af_0"

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
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(basecallQC)
    
    # ----------------------------------------------------------------------
    # 1. Input File Verification and Directory Setup
    # ----------------------------------------------------------------------
    # Define the exact user input files required from the working directory
    runXML <- "runParameters.xml"
    config <- "config.ini"
    sampleSheet <- "SampleSheet.csv"
    convStatsIn <- "ConversionStats.xml"
    demuxStatsIn <- "DemultiplexingStats.xml"
    
    # Verify that all required input files exist
    required_files <- c(runXML, config, sampleSheet, convStatsIn, demuxStatsIn)
    for (f in required_files) {
      if (!file.exists(f)) {
        stop(paste("Required input file missing from working directory:", f))
      }
    }
    
    # basecallQC expects ConversionStats.xml and DemultiplexingStats.xml
    # to be located in a 'Stats' subdirectory inside the specified outDir.
    outDir <- file.path(getwd(), "bcl2fastq_out")
    statsDir <- file.path(outDir, "Stats")
    dir.create(statsDir, recursive = TRUE, showWarnings = FALSE)
    
    # Copy the XML metrics files to the expected Stats directory structure
    file.copy(convStatsIn, file.path(statsDir, "ConversionStats.xml"), overwrite = TRUE)
    file.copy(demuxStatsIn, file.path(statsDir, "DemultiplexingStats.xml"), overwrite = TRUE)
    
    # ----------------------------------------------------------------------
    # 2. Run basecallQC Pipeline (Documented Code Workflow)
    # ----------------------------------------------------------------------
    # Initialize run parameters with the output directory specified
    bcl2fastqparams <- BCL2FastQparams(runXML, config, runDir=getwd(), outDir, verbose=FALSE)
    
    # Run the main pipeline
    bclQC <- basecallQC(bcl2fastqparams, RunMetaData=NULL, sampleSheet)
    
    # Extract basecalling and demultiplexing metrics
    bclMetrics <- baseCallMetrics(bcl2fastqparams)
    demuxMetrics <- demultiplexMetrics(bcl2fastqparams)
    
    # Generate summary tables (HTML interactive mode)
    summaryConvStatsTable(bclQC, output = "html")
    summaryDemuxTable(bclQC, output = "html")
    
    # Create QC plots
    passFilterBar(bclQC, groupBy="Sample", metricToPlot = "Yield")
    passFilterTilePlot(bclQC, metricToPlot = "Yield")
    demuxBarplot(bclQC, groupBy="Sample")
    
    # Generate HTML report
    reportBCL(bclQC)
    
    # ----------------------------------------------------------------------
    # 3. Export and Save Meaningful Results
    # ----------------------------------------------------------------------
    # Save core R objects
    saveRDS(bclQC, "bclQC_object.rds")
    saveRDS(bclMetrics, "bclMetrics.rds")
    saveRDS(demuxMetrics, "demuxMetrics.rds")
    
    # Save static versions of the summary tables to CSV
    tryCatch({
      convTableStatic <- summaryConvStatsTable(bclQC, output = "static")
      write.csv(convTableStatic, "summaryConvStatsTable.csv", row.names = FALSE)
    }, error = function(e) {
      warning("Could not write static Conversion Stats table: ", e\$message)
    })
    
    tryCatch({
      demuxTableStatic <- summaryDemuxTable(bclQC, output = "static")
      write.csv(demuxTableStatic, "summaryDemuxTable.csv", row.names = FALSE)
    }, error = function(e) {
      warning("Could not write static Demultiplexing Stats table: ", e\$message)
    })
    
    # Save interactive HTML tables if htmlwidgets is available
    if (requireNamespace("htmlwidgets", quietly = TRUE)) {
      tryCatch({
        convTableHTML <- summaryConvStatsTable(bclQC, output = "html")
        htmlwidgets::saveWidget(convTableHTML, "summaryConvStatsTable.html", selfcontained = TRUE)
      }, error = function(e) {
        warning("Could not save interactive Conversion Stats HTML table: ", e\$message)
      })
    
      tryCatch({
        demuxTableHTML <- summaryDemuxTable(bclQC, output = "html")
        htmlwidgets::saveWidget(demuxTableHTML, "summaryDemuxTable.html", selfcontained = TRUE)
      }, error = function(e) {
        warning("Could not save interactive Demultiplexing Stats HTML table: ", e\$message)
      })
    }
    
    # Save all generated plots to a single PDF file
    pdf("basecallQC_plots.pdf", width = 10, height = 8)
    
    tryCatch({
      p1 <- passFilterBar(bclQC, groupBy="Sample", metricToPlot = "Yield")
      print(p1)
    }, error = function(e) {
      warning("Error plotting passFilterBar: ", e\$message)
    })
    
    tryCatch({
      p2 <- passFilterTilePlot(bclQC, metricToPlot = "Yield")
      if (is.list(p2)) {
        for (p in p2) {
          if (!is.null(p)) print(p)
        }
      } else {
        print(p2)
      }
    }, error = function(e) {
      warning("Error plotting passFilterTilePlot: ", e\$message)
    })
    
    tryCatch({
      p3 <- demuxBarplot(bclQC, groupBy="Sample")
      print(p3)
    }, error = function(e) {
      warning("Error plotting demuxBarplot: ", e\$message)
    })
    
    dev.off()

    cat <<-END_VERSIONS > versions.yml
    "BIOC_BASECALLQC_BCL2FASTQ_QC_ANALYSIS_AND_REPORTING":
        basecallqc: \$(Rscript -e 'cat(as.character(packageVersion("basecallqc")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bcl2fastq_qc_analysis_and_reporting.csv versions.yml
    """
}

workflow BIOC_BASECALLQC_BCL2FASTQ_QC_ANALYSIS_AND_REPORTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ runParameters.xml, config.ini, SampleSheet.csv, ConversionStats.xml, DemultiplexingStats.xml ] ]

    main:
    BIOC_BASECALLQC_BCL2FASTQ_QC_ANALYSIS_AND_REPORTING(ch_input)

    emit:
    tables   = BIOC_BASECALLQC_BCL2FASTQ_QC_ANALYSIS_AND_REPORTING.out.tables
    plots    = BIOC_BASECALLQC_BCL2FASTQ_QC_ANALYSIS_AND_REPORTING.out.plots
    objects  = BIOC_BASECALLQC_BCL2FASTQ_QC_ANALYSIS_AND_REPORTING.out.objects
    versions = BIOC_BASECALLQC_BCL2FASTQ_QC_ANALYSIS_AND_REPORTING.out.versions
}
