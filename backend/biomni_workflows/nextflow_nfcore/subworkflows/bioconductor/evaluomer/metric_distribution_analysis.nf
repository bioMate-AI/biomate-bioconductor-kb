#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: evaluomeR — metric_distribution_analysis
// Visualize and analyze the distribution, range, and hierarchical clustering of bioinformatics metrics.
// Input: SummarizedExperiment
// Container: quay.io/biocontainers/bioconductor-evaluomer:1.26.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, evaluomeR
// Visualizations: box plot, cluster plot, violin plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Plot the minimum, maximum, and standard deviation of metrics using plotMetricsMinMax
//  * 2. [Visualization & Output] Generate boxplots of metric values using plotMetricsBoxplot
//  * 3. [Visualization & Output] Cluster metrics hierarchically using euclidean distance and Ward's method with plotMetricsCluster
//  * 4. [Visualization & Output] Generate violin plots of metric values using plotMetricsViolin

nextflow.enable.dsl = 2

process BIOC_EVALUOMER_METRIC_DISTRIBUTION_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("evaluomeR", "SummarizedExperiment")
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
    
    # Load required libraries
        library(SummarizedExperiment)
library(evaluomeR)
    
    # Define and locate the user input file
    input_file <- "SummarizedExperiment.rds"
    
    if (!file.exists(input_file)) {
      # Fallback to find any RDS file in the working directory if the exact name is different
      rds_files <- list.files(pattern = "\\\\.rds\$", ignore.case = TRUE)
      if (length(rds_files) > 0) {
        input_file <- rds_files[1]
      } else {
        stop("Error: SummarizedExperiment input file (RDS) not found in the working directory.")
      }
    }
    
    # Read the user input SummarizedExperiment
    se_input <- readRDS(input_file)
    
    # Assign the input object to the variables expected by the documented code
    ontMetrics <- se_input
    rnaMetrics <- se_input
    
    # 1. Plot the minimum, maximum, and standard deviation of metrics using plotMetricsMinMax
    pdf("plot_metrics_min_max.pdf")
    print(plotMetricsMinMax(ontMetrics))
    dev.off()
    
    # 2. Generate boxplots of metric values using plotMetricsBoxplot
    pdf("plot_metrics_boxplot.pdf")
    print(plotMetricsBoxplot(rnaMetrics))
    dev.off()
    
    # 3. Cluster metrics hierarchically using euclidean distance and Ward's method with plotMetricsCluster
    pdf("plot_metrics_cluster.pdf")
    print(plotMetricsCluster(ontMetrics))
    dev.off()
    
    # 4. Generate violin plots of metric values using plotMetricsViolin
    pdf("plot_metrics_violin.pdf")
    print(plotMetricsViolin(rnaMetrics))
    dev.off()
    
    # Export summary statistics of the metrics to a CSV file
    tryCatch({
      df_assay <- as.data.frame(SummarizedExperiment::assay(se_input))
      # Identify numeric columns (excluding ID column if present)
      numeric_cols <- sapply(df_assay, is.numeric)
      if (any(numeric_cols)) {
        summary_stats <- data.frame(
          Mean = colMeans(df_assay[, numeric_cols, drop = FALSE], na.rm = TRUE),
          SD = apply(df_assay[, numeric_cols, drop = FALSE], 2, sd, na.rm = TRUE),
          Min = apply(df_assay[, numeric_cols, drop = FALSE], 2, min, na.rm = TRUE),
          Max = apply(df_assay[, numeric_cols, drop = FALSE], 2, max, na.rm = TRUE)
        )
        write.csv(summary_stats, "metrics_summary_statistics.csv", row.names = TRUE)
      }
    }, error = function(e) {
      message("Could not generate summary statistics CSV: ", e\$message)
    })

    writeLines(c(
        '"BIOC_EVALUOMER_METRIC_DISTRIBUTION_ANALYSIS":',
        paste0('    evaluomeR: ', as.character(packageVersion('evaluomeR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_metric_distribution_analysis.csv versions.yml
    """
}

workflow BIOC_EVALUOMER_METRIC_DISTRIBUTION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ SummarizedExperiment ] ]

    main:
    BIOC_EVALUOMER_METRIC_DISTRIBUTION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_EVALUOMER_METRIC_DISTRIBUTION_ANALYSIS.out.tables
    plots    = BIOC_EVALUOMER_METRIC_DISTRIBUTION_ANALYSIS.out.plots
    objects  = BIOC_EVALUOMER_METRIC_DISTRIBUTION_ANALYSIS.out.objects
    versions = BIOC_EVALUOMER_METRIC_DISTRIBUTION_ANALYSIS.out.versions
}
