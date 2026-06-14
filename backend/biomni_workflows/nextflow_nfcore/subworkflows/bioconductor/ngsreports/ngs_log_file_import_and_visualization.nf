#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ngsreports — ngs_log_file_import_and_visualization
// Import and visualize log files from adapter trimming, mapping/alignment, and genome assembly tools.
// Input: trimmomatic_log.txt, bowtie_log.txt, star_log.out, flagstat.txt, dedup_metrics.txt, busco_log.txt, quast_log.tsv
// Container: quay.io/biocontainers/bioconductor-ngsreports:2.12.1--r45hdfd78af_0
// R packages: ggplot2, ngsReports
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_NGSREPORTS_NGS_LOG_FILE_IMPORT_AND_VISUALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-ngsreports:2.12.1--r45hdfd78af_0"

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
    .bm_deps <- c("ggplot2", "ngsReports")
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
    library(ngsReports)
    library(ggplot2)
    
    # ==========================================
    # USER INPUT FILES (from working directory)
    # ==========================================
    trimmomaticLogs <- "trimmomatic_log.txt"
    bowtieLogs      <- "bowtie_log.txt"
    starLog         <- "star_log.out"
    flagstatLog     <- "flagstat.txt"
    dupMetricsFile  <- "dedup_metrics.txt"
    buscoLog        <- "busco_log.txt"
    quastLog        <- "quast_log.tsv"
    
    # ==========================================
    # --- Import log files using importNgsLogs() ---
    # ==========================================
    
    # 1. Import Trimmomatic log
    df_trimmomatic <- importNgsLogs(trimmomaticLogs)
    write.csv(df_trimmomatic, "trimmomatic_parsed.csv", row.names = FALSE)
    
    # 2. Import Bowtie log
    df_bowtie <- importNgsLogs(bowtieLogs, type = "bowtie")
    write.csv(df_bowtie, "bowtie_parsed.csv", row.names = FALSE)
    
    # 3. Import STAR log
    df_star <- importNgsLogs(starLog, type = "star")
    write.csv(df_star, "star_parsed.csv", row.names = FALSE)
    
    # 4. Import Flagstat log
    df_flagstat <- importNgsLogs(flagstatLog, type = "flagstat")
    write.csv(df_flagstat, "flagstat_parsed.csv", row.names = FALSE)
    
    # 5. Import Picard Duplication Metrics log
    dupMetrics <- importNgsLogs(dupMetricsFile, type = "duplicationMetrics", which = "metrics")
    write.csv(dupMetrics, "duplication_metrics_parsed.csv", row.names = FALSE)
    
    
    # ==========================================
    # --- Plot alignment summaries using plotAlignmentSummary() ---
    # ==========================================
    
    # 1. Plot Bowtie alignment summary
    p_bowtie <- plotAlignmentSummary(bowtieLogs, type = "bowtie")
    ggsave("bowtie_alignment_summary.pdf", plot = p_bowtie, width = 8, height = 6)
    
    # 2. Plot STAR alignment summary
    p_star <- plotAlignmentSummary(starLog, type = "star")
    ggsave("star_alignment_summary.pdf", plot = p_star, width = 8, height = 6)
    
    
    # ==========================================
    # --- Plot assembly statistics using plotAssemblyStats() ---
    # ==========================================
    
    # 1. Plot BUSCO assembly completeness
    p_busco <- plotAssemblyStats(buscoLog, type = "busco")
    ggsave("busco_assembly_stats.pdf", plot = p_busco, width = 8, height = 6)
    
    # 2. Plot QUAST assembly statistics (default plot)
    p_quast <- plotAssemblyStats(quastLog, type = "quast")
    ggsave("quast_assembly_stats.pdf", plot = p_quast, width = 8, height = 6)
    
    # 3. Plot QUAST assembly statistics (parallel coordinate plot)
    p_quast_para <- plotAssemblyStats(quastLog, type = "quast", plotType = "paracoord")
    ggsave("quast_assembly_stats_paracoord.pdf", plot = p_quast_para, width = 8, height = 6)
    
    # Save all imported dataframes as an RDS object for downstream analysis
    saveRDS(
      list(
        trimmomatic = df_trimmomatic,
        bowtie = df_bowtie,
        star = df_star,
        flagstat = df_flagstat,
        duplicationMetrics = dupMetrics
      ),
      file = "imported_ngs_logs.rds"
    )

    writeLines(c(
        '"BIOC_NGSREPORTS_NGS_LOG_FILE_IMPORT_AND_VISUALIZATION":',
        paste0('        ngsreports: ', as.character(packageVersion("ngsreports")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ngs_log_file_import_and_visualization.csv versions.yml
    """
}

workflow BIOC_NGSREPORTS_NGS_LOG_FILE_IMPORT_AND_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ trimmomatic_log.txt, bowtie_log.txt, star_log.out, flagstat.txt, dedup_metrics.txt, busco_log.txt, quast_log.tsv ] ]

    main:
    BIOC_NGSREPORTS_NGS_LOG_FILE_IMPORT_AND_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_NGSREPORTS_NGS_LOG_FILE_IMPORT_AND_VISUALIZATION.out.tables
    plots    = BIOC_NGSREPORTS_NGS_LOG_FILE_IMPORT_AND_VISUALIZATION.out.plots
    objects  = BIOC_NGSREPORTS_NGS_LOG_FILE_IMPORT_AND_VISUALIZATION.out.objects
    versions = BIOC_NGSREPORTS_NGS_LOG_FILE_IMPORT_AND_VISUALIZATION.out.versions
}
