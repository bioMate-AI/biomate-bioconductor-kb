#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: erccdashboard — rnaseq_count_analysis
// Analyze unnormalized RNA-Seq count data with ERCC spike-ins to evaluate technical performance.
// Input: MET.CTL.countDat, MET.CTL.totalReads
// Container: quay.io/biocontainers/bioconductor-erccdashboard:1.44.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: erccdashboard, ggplot2, gridExtra
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load the input count data and optional normalization
//  * 2. [Visualization & Output] Run the complete analysis pipeline using runDashboard
//  * 3. [Visualization & Output] Summarize the results and visualize diagnostic plots
//  * 4. [Visualization & Output] Write named output files for the meaningful results

nextflow.enable.dsl = 2

process BIOC_ERCCDASHBOARD_RNASEQ_COUNT_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("erccdashboard", "gridExtra", "ggplot2")
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
        
        # Load required libraries
        library(erccdashboard)
        library(gridExtra)
        library(ggplot2)
        
        # --- Load the input count data and optional normalization ---
        if (file.exists("MET.CTL.countDat")) {
          # Read the RNA-Seq count table
          MET.CTL.countDat <- read.csv("MET.CTL.countDat", header = TRUE, check.names = FALSE, stringsAsFactors = FALSE)
          # If it was tab-separated instead of comma-separated
          if (ncol(MET.CTL.countDat) <= 1) {
            MET.CTL.countDat <- read.delim("MET.CTL.countDat", header = TRUE, check.names = FALSE, stringsAsFactors = FALSE)
          }
        } else {
          stop("Required input file 'MET.CTL.countDat' not found in the working directory.")
        }
        
        # Read the optional total reads vector if it exists
        if (file.exists("MET.CTL.totalReads")) {
          MET.CTL.totalReads <- scan("MET.CTL.totalReads", quiet = TRUE)
        } else {
          MET.CTL.totalReads <- NULL
        }
        
        # --- Run the complete analysis pipeline using runDashboard ---
        exDat <- runDashboard(datType="count", isNorm = FALSE,
                               exTable=MET.CTL.countDat,
                               repNormFactor=MET.CTL.totalReads,
                               filenameRoot="RatTox", sample1Name="MET",
                               sample2Name="CTL", erccmix="RatioPair",
                               erccdilution=1/100, spikeVol=1,
                               totalRNAmass=0.500, choseFDR=0.1)
        
        # --- Summarize the results and visualize diagnostic plots ---
        summary(exDat)
        
        # Open PDF device to save the diagnostic plots
        pdf("RatTox_diagnostic_plots.pdf", width = 8, height = 8)
        
        # Render and save the plots exactly as documented
        print(exDat\$Figures\$dynRangePlot)
        grid.arrange(exDat\$Figures\$rocPlot)
        grid.arrange(exDat\$Figures\$lodrERCCPlot)
        grid.arrange(exDat\$Figures\$maPlot)
        
        dev.off()
        
        # --- Write named output files for the meaningful results ---
        saveRDS(exDat, file = "RatTox_analysis_results.rds")
        
        if (!is.null(exDat\$Transcripts)) {
          # Write the data frame to CSV
          write.csv(exDat\$Transcripts, file = "RatTox_transcripts_summary.csv", row.names = FALSE)
        }
        
        cat("Pipeline completed successfully. Outputs saved to 'RatTox_diagnostic_plots.pdf', 'RatTox_analysis_results.rds', and 'RatTox_transcripts_summary.csv'.\n")

    writeLines(c(
        '"BIOC_ERCCDASHBOARD_RNASEQ_COUNT_ANALYSIS":',
        paste0('    erccdashboard: ', as.character(packageVersion('erccdashboard')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rnaseq_count_analysis.csv versions.yml
    """
}

workflow BIOC_ERCCDASHBOARD_RNASEQ_COUNT_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ MET.CTL.countDat, MET.CTL.totalReads ] ]

    main:
    BIOC_ERCCDASHBOARD_RNASEQ_COUNT_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_ERCCDASHBOARD_RNASEQ_COUNT_ANALYSIS.out.tables
    plots    = BIOC_ERCCDASHBOARD_RNASEQ_COUNT_ANALYSIS.out.plots
    objects  = BIOC_ERCCDASHBOARD_RNASEQ_COUNT_ANALYSIS.out.objects
    versions = BIOC_ERCCDASHBOARD_RNASEQ_COUNT_ANALYSIS.out.versions
}
