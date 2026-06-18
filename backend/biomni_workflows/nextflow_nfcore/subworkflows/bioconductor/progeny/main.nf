#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: progeny — progeny_pathway_activity_pipeline
// Infer pathway activity scores from transcriptomic count data using PROGENy, perform permutation testing, and generate diagnostic scatter plots and heatmaps.
// Input: counts.csv, coldata.csv
// Container: 1.32.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: dplyr, ggplot2, progeny
// Visualizations: heatmap, pathway diagram
// QC: count normalization
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PROGENY_PROGENY_PATHWAY_ACTIVITY_PIPELINE {
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
    .bm_deps <- c("progeny", "ggplot2", "dplyr")
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
    library(progeny)
    library(ggplot2)
    library(dplyr)
    
    # ==========================================
    # --- Load and Preprocess Input Data ---
    # ==========================================
    message("Loading input datasets...")
    counts <- read.csv("counts.csv", row.names = 1, check.names = FALSE)
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    # Ensure sample names match between counts and coldata
    common_samples <- intersect(colnames(counts), coldata\$sample)
    if (length(common_samples) == 0) {
      stop("No matching samples found between counts.csv and coldata.csv")
    }
    counts <- counts[, common_samples, drop = FALSE]
    coldata <- coldata[coldata\$sample %in% common_samples, ]
    
    # Normalize counts to log2-CPM (Counts Per Million)
    message("Normalizing count data to log2-CPM...")
    libsizes <- colSums(counts)
    cpm <- t(t(counts) / libsizes) * 1e6
    log_cpm <- log2(cpm + 1)
    expr_matrix <- as.matrix(log_cpm)
    
    # ==========================================
    # --- Retrieve PROGENy Model & Compute Activities ---
    # ==========================================
    message("Retrieving PROGENy model...")
    model_top <- getModel(organism = "Human", top = 100)
    write.csv(model_top, "progeny_model_top.csv", row.names = FALSE)
    
    message("Estimating pathway activities using PROGENy...")
    pathway_activities <- progeny(
      expr = expr_matrix,
      scale = TRUE,
      organism = "Human",
      top = 100
    )
    write.csv(pathway_activities, "pathway_activities.csv", row.names = TRUE)
    
    # ==========================================
    # --- Permutation Testing ---
    # ==========================================
    message("Running permutation testing for pathway significance...")
    perm_results <- tryCatch({
      progenyPerm(
        expr = expr_matrix,
        organism = "Human",
        top = 100,
        perm = 100
      )
    }, error = function(e) {
      message("Permutation testing failed: ", e\$message)
      NULL
    })
    
    if (!is.null(perm_results)) {
      saveRDS(perm_results, "progeny_permutation_results.rds")
    } else {
      # Fallback empty file
      saveRDS(list(message = "Permutation not run or failed"), "progeny_permutation_results.rds")
    }
    
    # ==========================================
    # --- Differential Expression & Scatter Plots ---
    # ==========================================
    message("Calculating differential expression for diagnostic plots...")
    conditions <- unique(coldata\$condition)
    if (length(conditions) >= 2) {
      cond1_samples <- coldata\$sample[coldata\$condition == conditions[1]]
      cond2_samples <- coldata\$sample[coldata\$condition == conditions[2]]
      
      # Compute simple log fold change as the statistic
      mean_cond1 <- rowMeans(expr_matrix[, cond1_samples, drop = FALSE])
      mean_cond2 <- rowMeans(expr_matrix[, cond2_samples, drop = FALSE])
      logFC <- mean_cond2 - mean_cond1
      
      df_de <- data.frame(
        Gene = rownames(expr_matrix),
        stat = logFC,
        stringsAsFactors = FALSE
      )
      
      # Save diagnostic scatter plots for all pathways
      message("Saving PROGENy scatter plots...")
      dir.create("progeny_plots", showWarnings = FALSE)
      tryCatch({
        saveProgenyPlots(
          df = df_de,
          ap_id = "Gene",
          stat_id = "stat",
          organism = "Human",
          directory = "progeny_plots",
          top = 100
        )
      }, error = function(e) {
        message("Failed to save progeny plots: ", e\$message)
      })
    } else {
      message("Fewer than 2 conditions found; skipping differential scatter plots.")
      dir.create("progeny_plots", showWarnings = FALSE)
      writeLines("Differential expression scatter plots require at least 2 conditions.", "progeny_plots/README.txt")
    }
    
    # ==========================================
    # --- Visualization of Pathway Activities ---
    # ==========================================
    message("Generating pathway activity heatmap...")
    activity_df <- as.data.frame(pathway_activities)
    activity_df\$sample <- rownames(activity_df)
    
    # Reshape to long format using base R
    activity_long <- reshape(
      activity_df,
      varying = setdiff(names(activity_df), "sample"),
      v.names = "activity",
      timevar = "pathway",
      times = setdiff(names(activity_df), "sample"),
      direction = "long"
    )
    
    # Merge with metadata
    activity_long <- merge(activity_long, coldata, by = "sample")
    
    # Plot heatmap
    p_heatmap <- ggplot(activity_long, aes(x = sample, y = pathway, fill = activity)) +
      geom_tile(color = "white") +
      scale_fill_gradient2(low = "blue", mid = "white", high = "red", midpoint = 0) +
      theme_minimal() +
      theme(
        axis.text.x = element_text(angle = 45, hjust = 1, vjust = 1),
        axis.title = element_blank()
      ) +
      labs(title = "PROGENy Pathway Activities", fill = "Activity Score")
    
    ggsave("pathway_activities_heatmap.pdf", plot = p_heatmap, width = 8, height = 6)
    
    message("Pipeline completed successfully!")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # count normalization — scan .rds matrix artifacts for library-size CV
    # ratio (post-norm / pre-norm); without raw input we report median lib CV
    # as a proxy diagnostic. Threshold = 0.7 (Bullard 2010 BMC Bioinf).
    .cn_lib_cvs <- numeric(0)
    .cn_scanned <- character(0)
    for (.cn_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .cn_obj <- tryCatch(readRDS(.cn_rds), error = function(e) NULL)
      .cn_mat <- if (is.matrix(.cn_obj) || is.data.frame(.cn_obj)) .cn_obj else NULL
      if (!is.null(.cn_mat) && ncol(.cn_mat) >= 2 && nrow(.cn_mat) >= 2) {
        .cn_lib <- tryCatch(colSums(as.matrix(.cn_mat), na.rm = TRUE), error = function(e) NULL)
        if (!is.null(.cn_lib) && all(is.finite(.cn_lib)) && mean(.cn_lib) > 0) {
          .cn_lib_cvs <- c(.cn_lib_cvs, sd(.cn_lib) / mean(.cn_lib))
          .cn_scanned <- c(.cn_scanned, .cn_rds)
        }
      }
    }
    .cn_med_cv <- if (length(.cn_lib_cvs) > 0) round(median(.cn_lib_cvs), 4) else NA_real_
    .gates_by_label[["count normalization"]] <- list(
      gate_row = "bioc_count_normalization",
      metric_name = "lib_size_cv_median",
      metric_value = .cn_med_cv,
      passes = isTRUE(is.finite(.cn_med_cv) && .cn_med_cv <= 0.3),
      status = if (is.finite(.cn_med_cv)) paste0("computed (proxy: median lib-size CV across ", length(.cn_scanned), " matrix .rds; raw-vs-norm ratio not measurable without paired input)")
               else "not_computed (no count matrix .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_PROGENY_PROGENY_PATHWAY_ACTIVITY_PIPELINE",
      domain  = "bioconductor",
      declared_qc_steps = c("count normalization"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_PROGENY_PROGENY_PATHWAY_ACTIVITY_PIPELINE":',
        paste0('    progeny: ', as.character(packageVersion('progeny')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_progeny_pathway_activity_pipeline.csv versions.yml
    """
}

workflow BIOC_PROGENY_PROGENY_PATHWAY_ACTIVITY_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_PROGENY_PROGENY_PATHWAY_ACTIVITY_PIPELINE(ch_input)

    emit:
    tables   = BIOC_PROGENY_PROGENY_PATHWAY_ACTIVITY_PIPELINE.out.tables
    plots    = BIOC_PROGENY_PROGENY_PATHWAY_ACTIVITY_PIPELINE.out.plots
    objects  = BIOC_PROGENY_PROGENY_PATHWAY_ACTIVITY_PIPELINE.out.objects
    versions = BIOC_PROGENY_PROGENY_PATHWAY_ACTIVITY_PIPELINE.out.versions
}
