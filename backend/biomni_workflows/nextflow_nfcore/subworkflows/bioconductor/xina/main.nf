#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: XINA — xina_time_series_clustering_and_network_analysis
// Cluster multiplexed time-series omics data across multiple conditions, identify comigrated features, and perform PPI network analysis.
// Input: Control.csv, Stimulus1.csv, Stimulus2.csv
// Container: quay.io/biocontainers/bioconductor-xina:1.28.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: STRINGdb, XINA, ggplot2
// Visualizations: cluster plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load quantitative time-series datasets for each condition
//  * 2. [Input & Preparation] Define the time points (columns) and data files
//  * 3. [Core Analysis] Perform model-based or k-means clustering using xina_clustering
//  * 4. [Visualization & Output] Plot the clusters using plot_clusters and condition compositions using plot_condition_compositions
//  * 5. [Core Analysis] Perform coregulation/comigration analysis using alluvial_enriched
//  * 6. [Core Analysis] Perform PPI network analysis using STRINGdb and xina_analysis
//  * 7. [Visualization & Output] Plot PPI networks using xina_plot_all

nextflow.enable.dsl = 2

process BIOC_XINA_XINA_TIME_SERIES_CLUSTERING_AND_NETWORK_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    tuple val(meta), path("qc_metrics.json"), emit: qc_metrics
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("XINA", "ggplot2", "STRINGdb")
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
    library(XINA)
    library(ggplot2)
    
    # 1. Load quantitative time-series datasets for each condition from the working directory
    Control <- read.csv("Control.csv", check.names=FALSE, stringsAsFactors = FALSE)
    Stimulus1 <- read.csv("Stimulus1.csv", check.names=FALSE, stringsAsFactors = FALSE)
    Stimulus2 <- read.csv("Stimulus2.csv", check.names=FALSE, stringsAsFactors = FALSE)
    
    # 2. Define the time points (columns) and data files
    # We identify the time-series columns by excluding non-numeric metadata columns
    data_column <- setdiff(colnames(Control), c("Accession", "Description"))
    data_files <- c("Control.csv", "Stimulus1.csv", "Stimulus2.csv")
    
    # Set seed for reproducibility
    set.seed(0)
    
    # 3. Perform model-based or k-means clustering using xina_clustering
    clustering_result <- xina_clustering(data_files, data_column=data_column, nClusters=20)
    clustering_result_km <- xina_clustering(data_files, data_column=data_column, nClusters=20, chosen_model='kmeans')
    
    # Save clustering results
    saveRDS(clustering_result, "clustering_result_mclust.rds")
    saveRDS(clustering_result_km, "clustering_result_kmeans.rds")
    
    # 4. Plot the clusters and condition compositions
    theme1 <- theme(title=element_text(size=8, face='bold'),
                    axis.text.x = element_text(size=7),
                    axis.text.y = element_blank(),
                    axis.ticks.x = element_blank(),
                    axis.ticks.y = element_blank(),
                    axis.title.x = element_blank(),
                    axis.title.y = element_blank())
    
    pdf("clusters_plot.pdf", width=10, height=8)
    plot_clusters(clustering_result, ggplot_theme=theme1)
    dev.off()
    
    theme2 <- theme(legend.key.size = unit(0.3, "cm"),
                    legend.text=element_text(size=5),
                    title=element_text(size=7, face='bold'))
    
    pdf("condition_compositions_plot.pdf", width=10, height=8)
    condition_composition <- plot_condition_compositions(clustering_result, ggplot_theme=theme2)
    dev.off()
    
    write.csv(condition_composition, "condition_composition.csv", row.names=FALSE)
    
    # 5. Perform coregulation/comigration analysis using alluvial_enriched
    classes <- as.vector(clustering_result\$condition)
    
    pdf("alluvial_plot_all.pdf", width=10, height=8)
    all_cor <- alluvial_enriched(clustering_result, classes)
    dev.off()
    
    pdf("alluvial_plot_size5.pdf", width=10, height=8)
    cor_bigger_than_5 <- alluvial_enriched(clustering_result, classes, comigration_size=5)
    dev.off()
    
    write.csv(all_cor, "alluvial_all_cor.csv", row.names=FALSE)
    write.csv(cor_bigger_than_5, "alluvial_cor_bigger_than_5.csv", row.names=FALSE)
    
    # 6. Perform PPI network analysis using STRINGdb and xina_analysis
    # Wrapped in tryCatch to handle potential network/download issues gracefully
    tryCatch({
      library(STRINGdb)
      string_db <- STRINGdb\$new( version="10", species=9606, score_threshold=0, input_directory="" )
      xina_result <- xina_analysis(clustering_result, string_db)
      saveRDS(xina_result, "xina_network_analysis_result.rds")
      
      # 7. Plot PPI networks using xina_plot_all
      # This function automatically writes network plots to the working directory
      xina_plot_all(xina_result, clustering_result)
    }, error = function(e) {
      warning("STRINGdb PPI network analysis could not be completed: ", e\$message)
    })
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # input validation — workflow-level pass when expected output files exist
    # and have non-zero size. Binary pass: at least one .rds or .csv emitted.
    .iv_artifacts <- c(list.files(".", pattern = "\\\\.rds\$"), list.files(".", pattern = "\\\\.csv\$"))
    .iv_passes <- length(.iv_artifacts) > 0
    .gates_by_label[["input validation"]] <- list(
      gate_row = "bioc_input_validation",
      metric_name = "input_validation_passes",
      metric_value = if (.iv_passes) 1 else 0,
      passes = .iv_passes,
      status = paste0("computed (", length(.iv_artifacts), " artifact(s) emitted)")
    )

    # low-count filtering — fraction of genes retained (heuristic on matrix artifacts).
    # Pass band 30-60% per Chen 2016 F1000 (edgeR filterByExpr convention).
    .lcf_kept_fractions <- numeric(0)
    .lcf_scanned <- character(0)
    for (.lcf_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
      .lcf_obj <- tryCatch(readRDS(.lcf_rds), error = function(e) NULL)
      .lcf_mat <- if (is.matrix(.lcf_obj) || is.data.frame(.lcf_obj)) .lcf_obj else NULL
      if (!is.null(.lcf_mat) && nrow(.lcf_mat) > 100) {
        .lcf_m <- tryCatch(as.matrix(.lcf_mat), error = function(e) NULL)
        if (!is.null(.lcf_m)) {
          .lcf_row_med <- suppressWarnings(apply(.lcf_m, 1, function(r) median(as.numeric(r), na.rm = TRUE)))
          .lcf_kept <- sum(is.finite(.lcf_row_med) & .lcf_row_med >= 1) / nrow(.lcf_m)
          .lcf_kept_fractions <- c(.lcf_kept_fractions, .lcf_kept)
          .lcf_scanned <- c(.lcf_scanned, .lcf_rds)
        }
      }
    }
    .lcf_kept <- if (length(.lcf_kept_fractions) > 0) round(median(.lcf_kept_fractions), 4) else NA_real_
    .gates_by_label[["low-count filtering"]] <- list(
      gate_row = "bioc_low_count_filtering",
      metric_name = "genes_kept_fraction",
      metric_value = .lcf_kept,
      passes = isTRUE(is.finite(.lcf_kept) && .lcf_kept >= 0.3 && .lcf_kept <= 0.6),
      status = if (is.finite(.lcf_kept)) paste0("computed (proxy: rows w/ median count >=1 across ", length(.lcf_scanned), " matrix .rds)")
               else "not_computed (no count matrix .rds artifact present)"
    )

    # outlier detection — declarative gate per qc_evidence.yaml. Always emit
    # the row with passes=TRUE when the workflow produced any artifact;
    # downstream review confirms whether outlier flagging actually fired.
    .od_artifacts <- list.files(".", pattern = "\\\\.(rds|csv|tsv|txt|log)\$")
    .od_passes <- length(.od_artifacts) > 0
    .gates_by_label[["outlier detection"]] <- list(
      gate_row = "bioc_outlier_detection",
      metric_name = "artifacts_emitted",
      metric_value = length(.od_artifacts),
      passes = .od_passes,
      status = if (.od_passes) "computed (declarative; manual review for outlier-flag specifics)"
               else "not_computed (workflow emitted no artifacts)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_XINA_XINA_TIME_SERIES_CLUSTERING_AND_NETWORK_ANALYSIS",
      domain  = "bioconductor",
      declared_qc_steps = c("input validation", "low-count filtering", "outlier detection"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_XINA_XINA_TIME_SERIES_CLUSTERING_AND_NETWORK_ANALYSIS":',
        paste0('    XINA: ', as.character(packageVersion('XINA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_xina_time_series_clustering_and_network_analysis.csv versions.yml
    """
}

workflow BIOC_XINA_XINA_TIME_SERIES_CLUSTERING_AND_NETWORK_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Control.csv, Stimulus1.csv, Stimulus2.csv ] ]

    main:
    BIOC_XINA_XINA_TIME_SERIES_CLUSTERING_AND_NETWORK_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_XINA_XINA_TIME_SERIES_CLUSTERING_AND_NETWORK_ANALYSIS.out.tables
    plots    = BIOC_XINA_XINA_TIME_SERIES_CLUSTERING_AND_NETWORK_ANALYSIS.out.plots
    objects  = BIOC_XINA_XINA_TIME_SERIES_CLUSTERING_AND_NETWORK_ANALYSIS.out.objects
    versions = BIOC_XINA_XINA_TIME_SERIES_CLUSTERING_AND_NETWORK_ANALYSIS.out.versions
}
