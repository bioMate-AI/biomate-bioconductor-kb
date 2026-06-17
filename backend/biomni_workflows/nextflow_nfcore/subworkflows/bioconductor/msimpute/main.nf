#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: msImpute — msimpute_proteomics_pipeline
// Preprocess proteomics intensity data, diagnose missingness patterns, perform MAR and MNAR low-rank imputations, and evaluate imputation quality using structural
// Input: intensity.csv, coldata.csv
// Container: 1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: msImpute
// Visualizations: plot (ggplot/base)
// QC: missing-value handling
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MSIMPUTE_MSIMPUTE_PROTEOMICS_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20-slim"

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
    .bm_deps <- c("msImpute")
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
    library(msImpute)
    
    # ==========================================
    # --- Load and Align Input Data ---
    # ==========================================
    message("Stage 1: Loading and aligning input data...")
    
    # Read intensity matrix and coldata
    intensity_df <- read.csv("intensity.csv", check.names = FALSE, stringsAsFactors = FALSE)
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    # Set feature_id as row names and convert to matrix
    if (!"feature_id" %in% colnames(intensity_df)) {
      stop("Input 'intensity.csv' must contain a 'feature_id' column.")
    }
    rownames(intensity_df) <- intensity_df\$feature_id
    intensity_df\$feature_id <- NULL
    y <- as.matrix(intensity_df)
    
    # Align samples between intensity matrix and coldata
    common_samples <- intersect(colnames(y), coldata\$sample)
    if (length(common_samples) == 0) {
      stop("No overlapping samples found between 'intensity.csv' and 'coldata.csv'.")
    }
    
    y <- y[, common_samples, drop = FALSE]
    coldata <- coldata[match(common_samples, coldata\$sample), ]
    group <- as.factor(coldata\$condition)
    
    # ==========================================
    # --- Preprocessing & Normalization ---
    # ==========================================
    message("Stage 2: Preprocessing and normalizing data...")
    
    # Convert any zero values to NA (msImpute expects NA for missing values)
    y[y == 0] <- NA
    
    # Log2 transform if data is not already log-transformed
    if (max(y, na.rm = TRUE) > 100) {
      message("Data appears to be on raw scale. Applying log2 transformation...")
      y <- log2(y + 0.25)
    }
    
    # Perform robust median normalization (base R implementation)
    col_medians <- apply(y, 2, median, na.rm = TRUE)
    grand_median <- median(col_medians)
    y_norm <- t(t(y) - col_medians + grand_median)
    
    # ==========================================
    # --- Missingness Pattern Diagnosis ---
    # ==========================================
    message("Stage 3: Diagnosing missingness patterns...")
    
    # Identify informative features exhibiting structured missingness (EBM method)
    hdp <- selectFeatures(y_norm, method = "ebm", group = group)
    write.csv(hdp, "selected_features.csv", row.names = TRUE)
    
    # ==========================================
    # --- Low-Rank Imputation (MAR & MNAR) ---
    # ==========================================
    message("Stage 4: Running low-rank imputations...")
    
    # 1. MAR Imputation (v2)
    message("Running MAR imputation (v2)...")
    y_mar <- msImpute(y_norm, method = "v2")
    write.csv(y_mar, "imputed_mar.csv", row.names = TRUE)
    
    # 2. MNAR Imputation (v2-mnar)
    message("Running MNAR imputation (v2-mnar)...")
    y_mnar <- msImpute(y_norm, method = "v2-mnar", group = group)
    write.csv(y_mnar, "imputed_mnar.csv", row.names = TRUE)
    
    # ==========================================
    # --- Structural Metrics Evaluation ---
    # ==========================================
    message("Stage 5: Evaluating structural preservation...")
    
    # Compute withinness and betweenness metrics (setting y = NULL to bypass python dependency)
    metrics_mar <- computeStructuralMetrics(y_mar, group, y = NULL)
    metrics_mnar <- computeStructuralMetrics(y_mnar, group, y = NULL)
    
    # Format and save structural metrics comparison
    metrics_df <- data.frame(
      Metric = c(paste0("withinness_", names(metrics_mar\$withinness)), "betweenness"),
      MAR = c(metrics_mar\$withinness, metrics_mar\$betweenness),
      MNAR = c(metrics_mnar\$withinness, metrics_mnar\$betweenness),
      stringsAsFactors = FALSE
    )
    write.csv(metrics_df, "structural_metrics.csv", row.names = FALSE)
    
    # ==========================================
    # --- Diagnostic Visualization ---
    # ==========================================
    message("Stage 6: Generating diagnostic plots...")
    
    pdf("diagnostic_plots.pdf", width = 12, height = 4)
    par(mfrow = c(1, 3))
    
    # Plot CV2 vs Mean log-expression for original, MAR, and MNAR imputed data
    plotCV2(y_norm, main = "Original Data (Normalized)")
    plotCV2(y_mar, main = "msImpute MAR (v2)")
    plotCV2(y_mnar, main = "msImpute MNAR (v2-mnar)")
    
    dev.off()
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_MSIMPUTE_MSIMPUTE_PROTEOMICS_PIPELINE":',
        paste0('    msImpute: ', as.character(packageVersion('msImpute')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_msimpute_proteomics_pipeline.csv versions.yml
    """
}

workflow BIOC_MSIMPUTE_MSIMPUTE_PROTEOMICS_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_MSIMPUTE_MSIMPUTE_PROTEOMICS_PIPELINE(ch_input)

    emit:
    tables   = BIOC_MSIMPUTE_MSIMPUTE_PROTEOMICS_PIPELINE.out.tables
    plots    = BIOC_MSIMPUTE_MSIMPUTE_PROTEOMICS_PIPELINE.out.plots
    objects  = BIOC_MSIMPUTE_MSIMPUTE_PROTEOMICS_PIPELINE.out.objects
    versions = BIOC_MSIMPUTE_MSIMPUTE_PROTEOMICS_PIPELINE.out.versions
}
