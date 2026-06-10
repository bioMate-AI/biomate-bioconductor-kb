#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rqc — simple_qc_report
// Quickly generate an HTML quality control report from a directory of FASTQ files.
// Input: folder, pattern
// Container: quay.io/biocontainers/bioconductor-rqc:1.44.0--r45ha27e39d_0
// R packages: ggplot2, Rqc
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RQC_SIMPLE_QC_REPORT {
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
    .bm_deps <- c("ggplot2", "Rqc")
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
    
    # User Input Configuration
    # Modify these variables to point to your local FASTQ directory and file pattern
    folder <- "."
    pattern <- ".fastq.gz"
    
    # 1. Load the package
    library(Rqc)
    library(ggplot2)
    
    # 2. Run the rqc function to process files and generate the HTML report
    # This matches the documented call: rqc(path = folder, pattern = ".fastq.gz")
    # We use the variable 'pattern' to allow user customization while keeping the exact argument names.
    html_report_path <- rqc(path = folder, pattern = pattern)
    message("HTML Report generated at: ", html_report_path)
    
    # 3. Advanced Workflow: Process files to extract and save specific tables and plots
    files <- list.files(folder, pattern = pattern, full.names = TRUE)
    
    if (length(files) > 0) {
      message("Processing ", length(files), " files for detailed outputs...")
      
      # Run rqcQA
      qa <- rqcQA(files, workers = 1)
      
      # Save the QA result object
      saveRDS(qa, file = "rqc_qa_result.rds")
      
      # Save File Information Table
      info_table <- perFileInformation(qa)
      write.csv(info_table, file = "rqc_file_information.csv", row.names = FALSE)
      
      # Save individual plots
      tryCatch({
        ggsave("rqc_read_quality_boxplot.pdf", plot = rqcReadQualityBoxPlot(qa), width = 8, height = 6)
      }, error = function(e) {
        message("Could not generate rqcReadQualityBoxPlot: ", e\$message)
      })
      
      tryCatch({
        ggsave("rqc_read_quality_plot.pdf", plot = rqcReadQualityPlot(qa), width = 8, height = 6)
      }, error = function(e) {
        message("Could not generate rqcReadQualityPlot: ", e\$message)
      })
      
      tryCatch({
        ggsave("rqc_cycle_average_quality_plot.pdf", plot = rqcCycleAverageQualityPlot(qa), width = 8, height = 6)
      }, error = function(e) {
        message("Could not generate rqcCycleAverageQualityPlot: ", e\$message)
      })
      
      tryCatch({
        ggsave("rqc_read_frequency_plot.pdf", plot = rqcReadFrequencyPlot(qa), width = 8, height = 6)
      }, error = function(e) {
        message("Could not generate rqcReadFrequencyPlot: ", e\$message)
      })
      
      tryCatch({
        if (length(qa) > 0) {
          ggsave("rqc_file_heatmap.pdf", plot = rqcFileHeatmap(qa[[1]]), width = 8, height = 6)
        }
      }, error = function(e) {
        message("Could not generate rqcFileHeatmap: ", e\$message)
      })
      
      tryCatch({
        ggsave("rqc_read_width_plot.pdf", plot = rqcReadWidthPlot(qa), width = 8, height = 6)
      }, error = function(e) {
        message("Could not generate rqcReadWidthPlot: ", e\$message)
      })
      
      tryCatch({
        ggsave("rqc_cycle_gc_plot.pdf", plot = rqcCycleGCPlot(qa), width = 8, height = 6)
      }, error = function(e) {
        message("Could not generate rqcCycleGCPlot: ", e\$message)
      })
      
      tryCatch({
        ggsave("rqc_cycle_quality_plot.pdf", plot = rqcCycleQualityPlot(qa), width = 8, height = 6)
      }, error = function(e) {
        message("Could not generate rqcCycleQualityPlot: ", e\$message)
      })
      
      tryCatch({
        ggsave("rqc_cycle_average_quality_pca_plot.pdf", plot = rqcCycleAverageQualityPcaPlot(qa), width = 8, height = 6)
      }, error = function(e) {
        message("Could not generate rqcCycleAverageQualityPcaPlot: ", e\$message)
      })
      
      tryCatch({
        ggsave("rqc_cycle_quality_boxplot.pdf", plot = rqcCycleQualityBoxPlot(qa), width = 8, height = 6)
      }, error = function(e) {
        message("Could not generate rqcCycleQualityBoxPlot: ", e\$message)
      })
      
      tryCatch({
        ggsave("rqc_cycle_base_calls_plot.pdf", plot = rqcCycleBaseCallsPlot(qa), width = 8, height = 6)
      }, error = function(e) {
        message("Could not generate rqcCycleBaseCallsPlot: ", e\$message)
      })
      
      tryCatch({
        ggsave("rqc_cycle_base_calls_line_plot.pdf", plot = rqcCycleBaseCallsLinePlot(qa), width = 8, height = 6)
      }, error = function(e) {
        message("Could not generate rqcCycleBaseCallsLinePlot: ", e\$message)
      })
      
      # Save custom cycle average quality plot and data
      tryCatch({
        df <- rqcCycleAverageQualityCalc(qa)
        write.csv(df, file = "rqc_cycle_average_quality_calc.csv", row.names = FALSE)
        
        pdf("rqc_custom_cycle_average_quality_plot.pdf", width = 8, height = 6)
        cycle <- as.numeric(levels(df\$cycle))[df\$cycle]
        plot(cycle, df\$quality, col = df\$filename, xlab = 'Cycle', ylab = 'Quality Score')
        dev.off()
      }, error = function(e) {
        message("Could not generate custom cycle average quality plot: ", e\$message)
      })
      
    } else {
      warning("No files matching pattern '", pattern, "' found in directory '", folder, "'. Detailed outputs skipped.")
    }

    cat <<-END_VERSIONS > versions.yml
    "BIOC_RQC_SIMPLE_QC_REPORT":
        rqc: \$(Rscript -e 'cat(as.character(packageVersion("rqc")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_simple_qc_report.csv versions.yml
    """
}

workflow BIOC_RQC_SIMPLE_QC_REPORT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ folder, pattern ] ]

    main:
    BIOC_RQC_SIMPLE_QC_REPORT(ch_input)

    emit:
    tables   = BIOC_RQC_SIMPLE_QC_REPORT.out.tables
    plots    = BIOC_RQC_SIMPLE_QC_REPORT.out.plots
    objects  = BIOC_RQC_SIMPLE_QC_REPORT.out.objects
    versions = BIOC_RQC_SIMPLE_QC_REPORT.out.versions
}
