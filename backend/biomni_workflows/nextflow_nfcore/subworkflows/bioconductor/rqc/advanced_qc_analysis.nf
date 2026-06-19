#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rqc — advanced_qc_analysis
// Perform step-by-step quality control analysis, generate individual diagnostic plots, and compile a customized HTML report.
// Input: files
// Container: quay.io/biocontainers/bioconductor-rqc:1.44.0--r45ha27e39d_0
// R packages: Rqc
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_RQC_ADVANCED_QC_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-rqc:1.44.0--r45ha27e39d_0"

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
    .bm_deps <- c("Rqc")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }

    # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
    for (.bm_d in list.files(".", full.names = TRUE)) {
      if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
        for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
          if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
        }
      }
    }
    
    # --- Load the package ---
    library(Rqc)
    
    # --- Define the vector of input file paths from the working ---
    # The pipeline reads FASTQ files (.fastq, .fastq.gz, .fq, .fq.gz) from the current working directory
    files <- list.files(getwd(), pattern = "\\\\.(fastq|fq)(\\\\.gz)?\$", full.names = TRUE)
    
    if (length(files) == 0) {
      stop("Error: No FASTQ files found in the working directory. Please place your FASTQ files in the working directory.")
    }
    
    # --- Process files using rqcQA to generate an RqcResultSet ---
    qa <- rqcQA(files, workers = 1)
    
    # Save the processed QA object as an RDS file
    saveRDS(qa, "rqc_qa_object.rds")
    
    # Save file information table to CSV
    file_info <- perFileInformation(qa)
    write.csv(file_info, "per_file_information.csv", row.names = FALSE)
    
    # Print table to console/log using knitr::kable as documented
    knitr::kable(perFileInformation(qa))
    
    # --- Generate individual diagnostic plots and save them to a ---
    pdf("rqc_diagnostic_plots.pdf", width = 11, height = 8.5)
    
    # Per Read Mean Quality Distribution
    print(rqcReadQualityBoxPlot(qa))
    
    # Average Quality
    print(rqcReadQualityPlot(qa))
    
    # Cycle-specific Average Quality
    print(rqcCycleAverageQualityPlot(qa))
    
    # Read Frequency
    print(rqcReadFrequencyPlot(qa))
    
    # Heatmap of top represented reads (only works with one result file)
    if (length(qa) >= 1) {
      print(rqcFileHeatmap(qa[[1]]))
    }
    
    # Read Length Distribution
    print(rqcReadWidthPlot(qa))
    
    # Cycle-specific GC Content
    print(rqcCycleGCPlot(qa))
    
    # Cycle-specific Quality Distribution
    print(rqcCycleQualityPlot(qa))
    
    # PCA Biplot
    print(rqcCycleAverageQualityPcaPlot(qa))
    
    # Cycle-specific Quality Distribution - Boxplot
    print(rqcCycleQualityBoxPlot(qa))
    
    # Cycle-specific Base Call Proportion
    print(rqcCycleBaseCallsPlot(qa))
    
    # Cycle-specific Base Call Proportion - Line Plot
    print(rqcCycleBaseCallsLinePlot(qa))
    
    dev.off()
    
    # --- Extract processed data for custom plotting using ---
    df <- rqcCycleAverageQualityCalc(qa)
    write.csv(df, "rqc_cycle_average_quality_calc.csv", row.names = FALSE)
    
    # Generate custom base plot
    pdf("rqc_custom_cycle_average_quality_plot.pdf", width = 8, height = 6)
    cycle <- as.numeric(levels(df\$cycle))[df\$cycle]
    plot(cycle, df\$quality, col = df\$filename, xlab = 'Cycle', ylab = 'Quality Score')
    dev.off()
    
    # Subset analysis
    pdf("rqc_subset_cycle_quality_plot.pdf", width = 8, height = 6)
    sublist <- qa[1]
    print(rqcCycleQualityPlot(sublist))
    dev.off()
    
    # --- Generate the HTML report using rqcReport ---
    reportFile <- rqcReport(qa)
    
    # Copy the default report to the working directory
    file.copy(reportFile, "rqc_report.html", overwrite = TRUE)
    
    # Attempt to browse the URL (wrapped to prevent failure in non-interactive environments)
    tryCatch({
      browseURL(reportFile)
    }, error = function(e) {
      message("Note: browseURL could not be opened automatically in this environment.")
    })
    
    # Create a minimal custom Rmd template to ensure the custom report compilation succeeds
    writeLines(c(
      "---",
      "title: \"Custom Rqc Quality Control Report\"",
      "output: html_document",
      "---",
      "",
      "### File Information Summary",
      "```{r, echo=FALSE}",
      "knitr::kable(perFileInformation(rqcResultSet))",
      "```",
      "",
      "### Read Quality Boxplot",
      "```{r, echo=FALSE, message=FALSE, warning=FALSE}",
      "print(rqcReadQualityBoxPlot(rqcResultSet))",
      "```"
    ), "custom_report.Rmd")
    
    # Generate personalized report using the custom template
    customReportFile <- rqcReport(qa, templateFile = "custom_report.Rmd")
    file.copy(customReportFile, "rqc_custom_report.html", overwrite = TRUE)

    writeLines(c(
        '"BIOC_RQC_ADVANCED_QC_ANALYSIS":',
        paste0('        rqc: ', as.character(packageVersion("rqc")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_advanced_qc_analysis.csv versions.yml
    """
}

workflow BIOC_RQC_ADVANCED_QC_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ files ] ]

    main:
    BIOC_RQC_ADVANCED_QC_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_RQC_ADVANCED_QC_ANALYSIS.out.tables
    plots    = BIOC_RQC_ADVANCED_QC_ANALYSIS.out.plots
    objects  = BIOC_RQC_ADVANCED_QC_ANALYSIS.out.objects
    versions = BIOC_RQC_ADVANCED_QC_ANALYSIS.out.versions
}
