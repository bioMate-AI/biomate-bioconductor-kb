#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: erccdashboard — microarray_analysis
// Analyze unnormalized microarray fluorescent intensity data with ERCC spike-ins.
// Input: UHRR.HBRR.arrayDat
// Container: quay.io/biocontainers/bioconductor-erccdashboard:1.44.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: erccdashboard, gridExtra
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load the input microarray data. 2. Run the complete analysis pipeline using runDashboard with datType="array". 3. Summarize and vi

nextflow.enable.dsl = 2

process BIOC_ERCCDASHBOARD_MICROARRAY_ANALYSIS {
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
    
    # Stage 1: Load the input microarray data
    if (file.exists("UHRR.HBRR.arrayDat")) {
      UHRR.HBRR.arrayDat <- tryCatch({
        read.table("UHRR.HBRR.arrayDat", header = TRUE, sep = "\t", check.names = FALSE, stringsAsFactors = FALSE)
      }, error = function(e) {
        read.csv("UHRR.HBRR.arrayDat", header = TRUE, check.names = FALSE, stringsAsFactors = FALSE)
      })
    } else {
      stop("Required input file 'UHRR.HBRR.arrayDat' not found in the working directory.")
    }
    
    # Stage 2: Run the complete analysis pipeline using runDashboard
    exDat <- runDashboard(datType="array", isNorm = FALSE,
                           exTable=UHRR.HBRR.arrayDat,
                           filenameRoot = "Lab13.array",
                           sample1Name = "UHRR",
                           sample2Name="HBRR",
                           erccmix = "RatioPair",
                           erccdilution = 1,
                           spikeVol = 50,
                           totalRNAmass = 2.5*10^(3),
                           choseFDR=0.01)
    
    # Stage 3: Summarize and visualize the results
    # Print summary to console
    summary(exDat)
    
    # Save the exDat object as an RDS file
    saveRDS(exDat, file = "Lab13.array.exDat.rds")
    
    # Save the diagnostic plots to a PDF file
    pdf("Lab13.array_diagnostic_plots.pdf", width = 10, height = 10)
    if (!is.null(exDat\$Figures\$dynRangePlot)) {
      grid.arrange(exDat\$Figures\$dynRangePlot)
    }
    if (!is.null(exDat\$Figures\$rocPlot)) {
      grid.arrange(exDat\$Figures\$rocPlot)
    }
    if (!is.null(exDat\$Figures\$lodrERCCPlot)) {
      grid.arrange(exDat\$Figures\$lodrERCCPlot)
    }
    if (!is.null(exDat\$Figures\$maPlot)) {
      grid.arrange(exDat\$Figures\$maPlot)
    }
    dev.off()
    
    # Save the transcripts data frame to a CSV file
    if (!is.null(exDat\$Transcripts)) {
      write.csv(exDat\$Transcripts, file = "Lab13.array_transcripts.csv", row.names = FALSE)
    }

    writeLines(c(
        '"BIOC_ERCCDASHBOARD_MICROARRAY_ANALYSIS":',
        paste0('    erccdashboard: ', as.character(packageVersion('erccdashboard')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_microarray_analysis.csv versions.yml
    """
}

workflow BIOC_ERCCDASHBOARD_MICROARRAY_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ UHRR.HBRR.arrayDat ] ]

    main:
    BIOC_ERCCDASHBOARD_MICROARRAY_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_ERCCDASHBOARD_MICROARRAY_ANALYSIS.out.tables
    plots    = BIOC_ERCCDASHBOARD_MICROARRAY_ANALYSIS.out.plots
    objects  = BIOC_ERCCDASHBOARD_MICROARRAY_ANALYSIS.out.objects
    versions = BIOC_ERCCDASHBOARD_MICROARRAY_ANALYSIS.out.versions
}
