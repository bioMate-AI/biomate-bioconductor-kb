#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: progeny — progeny_pathway_activity_pipeline
// Infer pathway activity scores from transcriptomic count data using PROGENy, perform permutation testing, and generate diagnostic scatter plots and heatmaps.
// Input: counts.csv, coldata.csv
// Container: 1.32.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: dplyr, ggplot2, progeny
// Visualizations: heatmap
// QC: count normalization
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PROGENY_PROGENY_PATHWAY_ACTIVITY_PIPELINE {
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("progeny", "ggplot2", "dplyr")
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
