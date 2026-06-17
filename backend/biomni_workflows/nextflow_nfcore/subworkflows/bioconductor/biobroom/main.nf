#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: biobroom — biobroom_transcriptomics_pipeline
// Perform differential expression analysis using DESeq2 and edgeR, compute q-values, and tidy all outputs using biobroom for downstream visualization.
// Input: counts.csv, coldata.csv
// Container: 1.42.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: DESeq2, biobroom, dplyr, edgeR, ggplot2, qvalue
// Visualizations: plot (ggplot/base)
// QC: TMM normalization, dispersion/size-factor estimation
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIOBROOM_BIOBROOM_TRANSCRIPTOMICS_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("biobroom", "DESeq2", "edgeR", "qvalue", "ggplot2", "dplyr")
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
    library(biobroom)
    library(DESeq2)
    library(edgeR)
    library(qvalue)
    library(ggplot2)
    library(dplyr)
    
    # Set options for biobroom to return standard data frames
    options(biobroom.return = "data.frame")
    
    # ==========================================
    # --- Load and Preprocess Input Data ---
    # ==========================================
    message("Stage 1: Loading input data...")
    
    if (!file.exists("counts.csv") || !file.exists("coldata.csv")) {
      stop("Required input files 'counts.csv' and/or 'coldata.csv' are missing.")
    }
    
    # Read counts and coldata
    counts_mat <- read.csv("counts.csv", row.names = 1, check.names = FALSE)
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    # Align samples between counts and coldata
    common_samples <- intersect(colnames(counts_mat), coldata\$sample)
    if (length(common_samples) == 0) {
      stop("No matching samples found between counts.csv columns and coldata.csv 'sample' column.")
    }
    
    counts_mat <- as.matrix(counts_mat[, common_samples, drop = FALSE])
    coldata <- coldata[coldata\$sample %in% common_samples, , drop = FALSE]
    rownames(coldata) <- coldata\$sample
    
    # Ensure condition is a factor
    coldata\$condition <- as.factor(coldata\$condition)
    
    # ==========================================
    # --- DESeq2 Analysis & Tidying ---
    # ==========================================
    message("Stage 2: Running DESeq2 analysis...")
    
    # Create DESeqDataSet
    dds <- DESeqDataSetFromMatrix(countData = counts_mat,
                                  colData = coldata,
                                  design = ~ condition)
    
    # Tidy the DESeqDataSet (extracts long-format counts)
    tidy_counts <- biobroom::tidy(dds)
    write.csv(tidy_counts, "deseq_tidy_counts.csv", row.names = FALSE)
    
    # Run differential expression
    dds <- DESeq(dds)
    res <- results(dds)
    
    # Tidy the DESeqResults
    tidy_deseq_res <- biobroom::tidy(res)
    write.csv(tidy_deseq_res, "deseq_tidy_results.csv", row.names = FALSE)
    
    # ==========================================
    # --- edgeR Analysis & Tidying ---
    # ==========================================
    message("Stage 3: Running edgeR analysis...")
    
    # Create DGEList
    y <- DGEList(counts = counts_mat, group = coldata\$condition)
    y <- calcNormFactors(y)
    y <- estimateDisp(y)
    et <- exactTest(y)
    
    # Tidy the DGEExact results
    tidy_edger_res <- biobroom::tidy(et)
    write.csv(tidy_edger_res, "edger_tidy_results.csv", row.names = FALSE)
    
    # Glance at the edgeR experiment summary
    glance_edger <- biobroom::glance(et, alpha = 0.05)
    
    # ==========================================
    # --- Multiple Hypothesis Testing with qvalue ---
    # ==========================================
    message("Stage 4: Estimating q-values...")
    
    # Extract p-values from DESeq2 results (excluding NAs)
    pvals <- tidy_deseq_res\$p.value
    pvals_clean <- pvals[!is.na(pvals)]
    gene_ids_clean <- tidy_deseq_res\$gene[!is.na(pvals)]
    
    # Run qvalue with error handling/fallback
    qobj <- tryCatch({
      qvalue(pvals_clean)
    }, error = function(e) {
      warning("Standard qvalue estimation failed. Attempting robust/pi0.method='bootstrap'...")
      tryCatch({
        qvalue(pvals_clean, pi0.method = "bootstrap")
      }, error = function(e2) {
        warning("Bootstrap qvalue failed. Falling back to pi0=1 (Benjamini-Hochberg equivalent)...")
        qvalue(pvals_clean, lambda = 0)
      })
    })
    
    # Tidy, Augment, and Glance at the qvalue object
    if (!is.null(qobj)) {
      # Create a mapping data frame to preserve gene IDs
      mapping_df <- data.frame(gene = gene_ids_clean, stringsAsFactors = FALSE)
      
      # Augment returns p-value, q-value, and local FDR mapped back to genes
      augmented_q <- biobroom::augment(qobj, data = mapping_df)
      write.csv(augmented_q, "qvalue_augmented_results.csv", row.names = FALSE)
      
      tidy_q <- biobroom::tidy(qobj)
      glance_q <- biobroom::glance(qobj)
    } else {
      # Fallback empty/dummy output if qvalue completely failed
      warning("qvalue object could not be created. Writing empty fallback file.")
      augmented_q <- data.frame(gene = gene_ids_clean, p.value = pvals_clean, q.value = NA, lfdr = NA)
      write.csv(augmented_q, "qvalue_augmented_results.csv", row.names = FALSE)
      tidy_q <- NULL
      glance_q <- NULL
    }
    
    # ==========================================
    # --- Visualization & Diagnostics ---
    # ==========================================
    message("Stage 5: Generating diagnostic plots...")
    
    pdf("analysis_plots.pdf", width = 10, height = 8)
    
    # 1. DESeq2 Volcano Plot
    p1 <- ggplot(tidy_deseq_res, aes(x = estimate, y = -log10(p.value))) +
      geom_point(aes(color = p.value < 0.05), alpha = 0.6) +
      scale_color_manual(values = c("black", "red")) +
      labs(title = "DESeq2 Volcano Plot (Tidied Data)",
           x = "Log2 Fold Change (Estimate)",
           y = "-log10(P-value)",
           color = "Significant (p < 0.05)") +
      theme_minimal()
    print(p1)
    
    # 2. edgeR Volcano Plot
    p2 <- ggplot(tidy_edger_res, aes(x = estimate, y = -log10(p.value))) +
      geom_point(aes(color = p.value < 0.05), alpha = 0.6) +
      scale_color_manual(values = c("black", "blue")) +
      labs(title = "edgeR Volcano Plot (Tidied Data)",
           x = "Log2 Fold Change (Estimate)",
           y = "-log10(P-value)",
           color = "Significant (p < 0.05)") +
      theme_minimal()
    print(p2)
    
    # 3. P-values vs Q-values Comparison Plot
    if (!is.null(qobj)) {
      p3 <- ggplot(augmented_q, aes(x = p.value, y = q.value)) +
        geom_point(color = "purple", alpha = 0.5) +
        labs(title = "P-values versus Computed Q-values (Augmented Data)",
             x = "Nominal P-value",
             y = "Storey's Q-value") +
        theme_minimal()
      print(p3)
    }
    
    dev.off()
    
    message("Pipeline completed successfully!")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # TMM normalization — DGEList\$samples\$norm.factors set (Robinson & Oshlack 2010).
    .tmm_factors <- NULL; .tmm_n_nontrivial <- NA_real_
    for (.tmm_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .tmm_obj <- tryCatch(readRDS(.tmm_rds), error = function(e) NULL)
      if (!is.null(.tmm_obj) && inherits(.tmm_obj, "DGEList")) {
        .tmm_f <- tryCatch(.tmm_obj\$samples\$norm.factors, error = function(e) NULL)
        if (!is.null(.tmm_f) && length(.tmm_f) > 0) {
          .tmm_factors <- .tmm_f; .tmm_n_nontrivial <- sum(abs(.tmm_f - 1.0) > 1e-6); break
        }
      }
    }
    .gates_by_label[["TMM normalization"]] <- list(
      gate_row = "bioc_tmm_normalization",
      metric_name = "n_nontrivial_norm_factors",
      metric_value = .tmm_n_nontrivial,
      passes = isTRUE(is.finite(.tmm_n_nontrivial) && .tmm_n_nontrivial > 0),
      status = if (is.finite(.tmm_n_nontrivial)) paste0("computed (n=", length(.tmm_factors), ", nontrivial=", .tmm_n_nontrivial, ")")
               else "not_computed (no DGEList .rds artifact present)"
    )

    # dispersion/size-factor estimation — object-type-aware. Try DESeq2
    # DESeqDataSet (mcols\$dispOutlier), then edgeR DGEList (common.dispersion).
    .dsf_value <- NA_real_; .dsf_kind <- "none"
    for (.dsf_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .dsf_obj <- tryCatch(readRDS(.dsf_rds), error = function(e) NULL)
      if (!is.null(.dsf_obj)) {
        if (inherits(.dsf_obj, "DESeqDataSet")) {
          .dsf_o <- tryCatch(mcols(.dsf_obj)\$dispOutlier, error = function(e) NULL)
          if (!is.null(.dsf_o)) { .dsf_value <- round(mean(.dsf_o, na.rm = TRUE), 4); .dsf_kind <- "deseq2"; break }
        } else if (inherits(.dsf_obj, "DGEList")) {
          .dsf_v <- tryCatch(.dsf_obj\$common.dispersion, error = function(e) NULL)
          if (!is.null(.dsf_v) && is.finite(.dsf_v)) { .dsf_value <- round(sqrt(.dsf_v), 4); .dsf_kind <- "edger_bcv"; break }
        }
      }
    }
    .gates_by_label[["dispersion/size-factor estimation"]] <- list(
      gate_row = "bioc_dispersion_size_factor",
      metric_name = if (.dsf_kind == "edger_bcv") "common_bcv" else "disp_outlier_fraction",
      metric_value = .dsf_value,
      passes = isTRUE(
        (.dsf_kind == "deseq2" && is.finite(.dsf_value) && .dsf_value <= 0.01) ||
        (.dsf_kind == "edger_bcv" && is.finite(.dsf_value) && .dsf_value > 0 && .dsf_value < 1.0)
      ),
      status = if (is.finite(.dsf_value)) paste0("computed (", .dsf_kind, ")")
               else "not_computed (no DESeqDataSet/DGEList .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_BIOBROOM_BIOBROOM_TRANSCRIPTOMICS_PIPELINE",
      domain  = "bioconductor",
      declared_qc_steps = c("TMM normalization", "dispersion/size-factor estimation"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_BIOBROOM_BIOBROOM_TRANSCRIPTOMICS_PIPELINE":',
        paste0('    biobroom: ', as.character(packageVersion('biobroom')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biobroom_transcriptomics_pipeline.csv versions.yml
    """
}

workflow BIOC_BIOBROOM_BIOBROOM_TRANSCRIPTOMICS_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_BIOBROOM_BIOBROOM_TRANSCRIPTOMICS_PIPELINE(ch_input)

    emit:
    tables   = BIOC_BIOBROOM_BIOBROOM_TRANSCRIPTOMICS_PIPELINE.out.tables
    plots    = BIOC_BIOBROOM_BIOBROOM_TRANSCRIPTOMICS_PIPELINE.out.plots
    objects  = BIOC_BIOBROOM_BIOBROOM_TRANSCRIPTOMICS_PIPELINE.out.objects
    versions = BIOC_BIOBROOM_BIOBROOM_TRANSCRIPTOMICS_PIPELINE.out.versions
}
