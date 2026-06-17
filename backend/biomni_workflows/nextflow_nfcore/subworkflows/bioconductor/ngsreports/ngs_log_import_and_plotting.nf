#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ngsReports — ngs_log_import_and_plotting
// Import and visualize log files from adapter removal, mapping, alignment, and genome assembly tools.
// Input: Sample1.trimmomaticPE.txt, bowtiePE.txt, log.final.out, flagstat.txt, Dedup_metrics.txt, short_summary_Dmelanogaster_Busco.txt, quast1.tsv
// Container: quay.io/biocontainers/bioconductor-ngsreports:2.12.1--r45hdfd78af_0
// R packages: dplyr, ggplot2, ngsReports
// Bioconductor: 3.20 | R: 4.4
// Requires: dplyr, ggplot2, ngsReports
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Import adapter removal/trimming logs
//  * 2. [Input & Preparation] Import mapping and alignment logs
//  * 3. [Visualization & Output] Plot alignment summaries
//  * 4. [Visualization & Output] Plot genome assembly statistics

nextflow.enable.dsl = 2

process BIOC_NGSREPORTS_NGS_LOG_IMPORT_AND_PLOTTING {
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
    .bm_deps <- c("dplyr", "ggplot2", "ngsReports")
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
    library(ngsReports)
    library(ggplot2)
    library(dplyr)
    
    # ==========================================
    # 1. Import adapter removal/trimming logs
    # ==========================================
    
    # Define the input file for Trimmomatic
    trimmomaticLogs <- "Sample1.trimmomaticPE.txt"
    
    # Import the log file
    trimmomatic_df <- importNgsLogs(trimmomaticLogs)
    
    # Save the imported data frame to a CSV file
    write.csv(trimmomatic_df, "trimmomatic_logs_imported.csv", row.names = FALSE)
    
    
    # ==========================================
    # 2. Import mapping and alignment logs
    # ==========================================
    
    # Define the input file for Bowtie (using only the user-specified bowtiePE.txt)
    bowtieLogs <- "bowtiePE.txt"
    
    # Import Bowtie log
    bowtie_df <- importNgsLogs(bowtieLogs, type = "bowtie")
    write.csv(bowtie_df, "bowtie_logs_imported.csv", row.names = FALSE)
    
    # Define the input file for STAR
    starLog <- "log.final.out"
    
    # Import STAR log
    star_df <- importNgsLogs(starLog, type = "star")
    write.csv(star_df, "star_logs_imported.csv", row.names = FALSE)
    
    # Define the input file for Samtools flagstat
    flagstatLog <- "flagstat.txt"
    
    # Import flagstat log
    flagstat_df <- importNgsLogs(flagstatLog, type = "flagstat")
    write.csv(flagstat_df, "flagstat_logs_imported.csv", row.names = FALSE)
    
    # Define the input file for Picard duplication metrics
    fl <- "Dedup_metrics.txt"
    
    # Import Picard duplication metrics
    dupMetrics <- importNgsLogs(fl, type = "duplicationMetrics", which = "metrics")
    write.csv(dupMetrics, "dup_metrics_imported.csv", row.names = FALSE)
    
    
    # ==========================================
    # 3. Plot alignment summaries
    # ==========================================
    
    # Plot Bowtie alignment summary and save to PDF
    p_bowtie <- plotAlignmentSummary(bowtieLogs, type = "bowtie")
    ggsave("plot_alignment_summary_bowtie.pdf", plot = p_bowtie, width = 8, height = 6)
    
    # Plot STAR alignment summary and save to PDF
    p_star <- plotAlignmentSummary(starLog, type = "star")
    ggsave("plot_alignment_summary_star.pdf", plot = p_star, width = 8, height = 6)
    
    
    # ==========================================
    # 4. Plot genome assembly statistics
    # ==========================================
    
    # Define the input file for BUSCO
    buscoLog <- "short_summary_Dmelanogaster_Busco.txt"
    
    # Plot BUSCO assembly stats and save to PDF
    p_busco <- plotAssemblyStats(buscoLog, type = "busco")
    ggsave("plot_assembly_stats_busco.pdf", plot = p_busco, width = 8, height = 6)
    
    # Define the input file for Quast (using only the user-specified quast1.tsv)
    quastLog <- "quast1.tsv"
    
    # Plot Quast assembly stats (default plot type) and save to PDF
    p_quast_default <- plotAssemblyStats(quastLog, type = "quast")
    ggsave("plot_assembly_stats_quast_default.pdf", plot = p_quast_default, width = 8, height = 6)
    
    # Plot Quast assembly stats (parallel coordinate plot type) and save to PDF
    p_quast_paracoord <- plotAssemblyStats(quastLog, type = "quast", plotType = "paracoord")
    ggsave("plot_assembly_stats_quast_paracoord.pdf", plot = p_quast_paracoord, width = 8, height = 6)

    writeLines(c(
        '"BIOC_NGSREPORTS_NGS_LOG_IMPORT_AND_PLOTTING":',
        paste0('    ngsReports: ', as.character(packageVersion('ngsReports')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ngs_log_import_and_plotting.csv versions.yml
    """
}

workflow BIOC_NGSREPORTS_NGS_LOG_IMPORT_AND_PLOTTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Sample1.trimmomaticPE.txt, bowtiePE.txt, log.final.out, flagstat.txt, Dedup_metrics.txt, short_summary_Dmelanogaster_Busco.txt, quast1.tsv ] ]

    main:
    BIOC_NGSREPORTS_NGS_LOG_IMPORT_AND_PLOTTING(ch_input)

    emit:
    tables   = BIOC_NGSREPORTS_NGS_LOG_IMPORT_AND_PLOTTING.out.tables
    plots    = BIOC_NGSREPORTS_NGS_LOG_IMPORT_AND_PLOTTING.out.plots
    objects  = BIOC_NGSREPORTS_NGS_LOG_IMPORT_AND_PLOTTING.out.objects
    versions = BIOC_NGSREPORTS_NGS_LOG_IMPORT_AND_PLOTTING.out.versions
}
