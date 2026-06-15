#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cfdnapro — multi_cohort_comparison
// Compare median size metrics, modal fragment sizes, and inter-peak/valley distances across multiple cohorts.
// Input: data_path
// Container: quay.io/biocontainers/bioconductor-cfdnapro:1.16.1--r45hdfd78af_0
// R packages: cfDNAPro, dplyr, ggplot2, ggpubr, scales
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CFDNAPRO_MULTI_COHORT_COMPARISON {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-cfdnapro:1.16.1--r45hdfd78af_0"

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
    .bm_deps <- c("cfDNAPro", "dplyr", "ggplot2", "ggpubr", "scales")
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
    suppressPackageStartupMessages({
      library(cfDNAPro)
      library(dplyr)
      library(ggplot2)
      library(scales)
      library(ggpubr)
    })
    
    # Define input path
    data_path <- "data_path"
    
    # Validate input directory
    if (!dir.exists(data_path)) {
      stop(paste("Error: Input directory '", data_path, "' does not exist in the working directory.", sep = ""))
    }
    
    # Dynamically determine cohort names from sub-folders to establish the order
    order <- list.dirs(data_path, full.names = FALSE, recursive = FALSE)
    order <- order[order != ""]
    
    if (length(order) == 0) {
      stop("Error: No cohort sub-folders found in 'data_path'.")
    }
    
    message("Detected cohorts: ", paste(order, collapse = ", "))
    
    # ==========================================
    # --- Calculate and plot median size metrics across cohorts ---
    # ==========================================
    message("Stage 1: Calculating and plotting median size metrics...")
    
    compare_grps <- callMetrics(data_path) %>% plotMetrics(order = order)
    
    # Save the metrics data object
    saveRDS(compare_grps, "median_metrics_results.rds")
    
    # Modify and save the plots
    p1 <- compare_grps\$median_prop_plot +
      ylim(c(0, 0.028)) +
      theme(axis.title.x = element_blank(),
            axis.title.y = element_text(size = 12, face = "bold")) +
      theme(legend.position = c(0.7, 0.5),
            legend.text = element_text(size = 11),
            legend.title = element_blank())
    
    p2 <- compare_grps\$median_cdf_plot +
      scale_y_continuous(labels = scales::number_format(accuracy = 0.001)) +
      theme(axis.title = element_text(size = 12, face = "bold")) +
      theme(legend.position = c(0.7, 0.5),
            legend.text = element_text(size = 11),
            legend.title = element_blank())
    
    suppressWarnings({
      median_grps <- ggpubr::ggarrange(p1, p2, label.x = 0.3, ncol = 1, nrow = 2)
    })
    
    pdf("median_size_metrics_comparison.pdf", width = 8, height = 10)
    suppressWarnings(print(median_grps))
    dev.off()
    
    
    # ==========================================
    # --- Calculate and plot modal fragment sizes ---
    # ==========================================
    message("Stage 2: Calculating and plotting modal fragment sizes...")
    
    # Calculate modes
    modes_df <- callMode(data_path)
    write.csv(modes_df, "modal_fragment_sizes.csv", row.names = FALSE)
    
    # Generate mode bin chart
    mode_bin <- modes_df %>% plotMode(order = order, hline = c(167, 111, 81))
    
    # Generate mode stacked bar chart
    mode_stacked <- modes_df %>% 
      plotModeSummary(order = order, mode_partition = list(c(166, 167)))
    
    # Modify stacked plot
    mode_stacked <- mode_stacked + theme(legend.position = "top")
    
    # Save plots to PDF
    pdf("modal_fragment_size_plots.pdf", width = 8, height = 6)
    suppressWarnings(print(mode_bin))
    suppressWarnings(print(mode_stacked))
    dev.off()
    
    
    # ==========================================
    # --- Calculate and plot inter-peak distances ---
    # ==========================================
    message("Stage 3: Calculating and plotting inter-peak distances...")
    
    peaks_df <- callPeakDistance(path = data_path, limit = c(50, 135))
    write.csv(peaks_df, "inter_peak_distances.csv", row.names = FALSE)
    
    inter_peak_dist <- peaks_df %>%
      plotPeakDistance(order = order) +
      labs(y = "Fraction") +
      theme(axis.title = element_text(size = 12, face = "bold"),
            legend.title = element_blank(),
            legend.position = c(0.91, 0.5),
            legend.text = element_text(size = 11))
    
    pdf("inter_peak_distance_plot.pdf", width = 8, height = 6)
    suppressWarnings(print(inter_peak_dist))
    dev.off()
    
    
    # ==========================================
    # --- Calculate and plot inter-valley distances ---
    # ==========================================
    message("Stage 4: Calculating and plotting inter-valley distances...")
    
    valleys_df <- callValleyDistance(path = data_path, limit = c(50, 135))
    write.csv(valleys_df, "inter_valley_distances.csv", row.names = FALSE)
    
    inter_valley_dist <- valleys_df %>%
      plotValleyDistance(order = order) +
      labs(y = "Fraction") +
      theme(axis.title = element_text(size = 12, face = "bold"),
            legend.title = element_blank(),
            legend.position = c(0.91, 0.5),
            legend.text = element_text(size = 11))
    
    pdf("inter_valley_distance_plot.pdf", width = 8, height = 6)
    suppressWarnings(print(inter_valley_dist))
    dev.off()
    
    message("Pipeline complete. All outputs successfully generated.")

    writeLines(c(
        '"BIOC_CFDNAPRO_MULTI_COHORT_COMPARISON":',
        paste0('        cfdnapro: ', as.character(packageVersion("cfdnapro")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multi_cohort_comparison.csv versions.yml
    """
}

workflow BIOC_CFDNAPRO_MULTI_COHORT_COMPARISON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ data_path ] ]

    main:
    BIOC_CFDNAPRO_MULTI_COHORT_COMPARISON(ch_input)

    emit:
    tables   = BIOC_CFDNAPRO_MULTI_COHORT_COMPARISON.out.tables
    plots    = BIOC_CFDNAPRO_MULTI_COHORT_COMPARISON.out.plots
    objects  = BIOC_CFDNAPRO_MULTI_COHORT_COMPARISON.out.objects
    versions = BIOC_CFDNAPRO_MULTI_COHORT_COMPARISON.out.versions
}
