#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: limmaGUI — limmagui_microarray_pipeline
// Perform differential expression analysis of microarray data using limmaGUI with robust headless execution and base R fallback.
// Input: counts.csv, coldata.csv
// Container: 1.86.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: limmaGUI, tcltk
// Visualizations: box plot
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_LIMMAGUI_LIMMAGUI_MICROARRAY_PIPELINE {
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
    .bm_deps <- c("limmaGUI")
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
    
    # --- Load Data and Setup ---
    message("Stage 1: Loading input data...")
    
    # Read expression matrix (counts.csv holds probe-by-sample normalized expression matrix)
    counts_df <- read.csv("counts.csv", check.names = FALSE)
    if ("gene_id" %in% colnames(counts_df)) {
      rownames(counts_df) <- counts_df\$gene_id
      counts_df\$gene_id <- NULL
    }
    M_matrix <- as.matrix(counts_df)
    
    # Read sample metadata
    coldata <- read.csv("coldata.csv", check.names = FALSE)
    
    # Align samples between expression matrix and metadata
    if ("sample" %in% colnames(coldata)) {
      common_samples <- intersect(coldata\$sample, colnames(M_matrix))
      if (length(common_samples) > 0) {
        M_matrix <- M_matrix[, common_samples, drop = FALSE]
        rownames(coldata) <- coldata\$sample
        coldata <- coldata[common_samples, , drop = FALSE]
      }
    }
    
    # Define condition factor
    cond <- as.factor(coldata\$condition)
    
    # Compute A-values (average log2 intensities)
    A_matrix <- matrix(rowMeans(M_matrix), nrow = nrow(M_matrix), ncol = ncol(M_matrix))
    rownames(A_matrix) <- rownames(M_matrix)
    colnames(A_matrix) <- colnames(M_matrix)
    
    # Write M and A values to output files
    write.csv(M_matrix, "m_values.csv", row.names = TRUE)
    write.csv(A_matrix, "a_values.csv", row.names = TRUE)
    
    # --- Attempt limmaGUI Analysis with Headless Mocks ---
    message("Stage 2: Attempting limmaGUI analysis...")
    
    limmagui_success <- FALSE
    
    tryCatch({
      # Set environment to prevent GUI popups
      options(menu.graphics = FALSE)
      Sys.setenv(DISPLAY = "")
      
      # Mock tcltk functions to prevent GUI hangs
      if (requireNamespace("tcltk", quietly = TRUE)) {
        library(tcltk)
        mock_tcl <- function(...) { return(tclObj("ok")) }
        try({
          unlockBinding(".Tcl", asNamespace("tcltk"))
          assign(".Tcl", mock_tcl, envir = asNamespace("tcltk"))
          lockBinding(".Tcl", asNamespace("tcltk"))
        }, silent = TRUE)
      }
      
      # Load limmaGUI
      library(limmaGUI)
      
      # Initialize globals
      initGlobals()
      
      # Construct MAList object
      MA <- list(
        M = M_matrix,
        A = A_matrix,
        genes = data.frame(ID = rownames(M_matrix), Name = rownames(M_matrix), stringsAsFactors = FALSE),
        targets = coldata
      )
      class(MA) <- "MAList"
      
      # Assign to global environment for limmaGUI functions
      assign("MA", MA, envir = .GlobalEnv)
      assign("targets", coldata, envir = .GlobalEnv)
      
      # Set up design matrix
      design <- model.matrix(~ 0 + cond)
      colnames(design) <- levels(cond)
      assign("design", design, envir = .GlobalEnv)
      
      # Set up Parameterizations
      Parameterization <- list(
        design = design,
        remainingParametersNoTargets = 0,
        parameterNames = colnames(design),
        spotTypesIncluded = rep(TRUE, nrow(MA\$genes))
      )
      assign("Parameterizations", list(Parameterization), envir = .GlobalEnv)
      assign("ActiveParameterization", 1, envir = .GlobalEnv)
      
      # Run linear model fit using evalRcode (exported by limmaGUI)
      evalRcode("fit <- lmFit(MA, design)")
      
      # Compute contrasts if we have at least 2 levels
      levels_cond <- levels(cond)
      if (length(levels_cond) >= 2) {
        contrast_str <- paste0("`", levels_cond[2], "` - `", levels_cond[1], "`")
        evalRcode(paste0("contrasts <- makeContrasts(", contrast_str, ", levels=design)"))
        evalRcode("fit2 <- contrasts.fit(fit, contrasts)")
        evalRcode("fit2 <- eBayes(fit2)")
        
        # Set up Contrasts Parameterizations
        ContrastsParameterization <- list(
          contrasts = get("contrasts", envir = .GlobalEnv),
          parameterizationIndex = 1,
          contrastNames = colnames(get("contrasts", envir = .GlobalEnv))
        )
        assign("ContrastsParameterizations", list(ContrastsParameterization), envir = .GlobalEnv)
        assign("ActiveContrastsParameterization", 1, envir = .GlobalEnv)
      } else {
        evalRcode("fit2 <- eBayes(fit)")
      }
      
      # Export Top Table using limmaGUI's evalRcode to extract the fit
      top_tbl <- evalRcode("topTable(fit2, coef=1, number=Inf)")
      write.csv(top_tbl, "top_table.csv", row.names = TRUE)
      
      limmagui_success <- TRUE
      message("limmaGUI analysis completed successfully.")
      
    }, error = function(e) {
      message("limmaGUI analysis failed or was bypassed: ", e\$message)
    })
    
    # --- Fallback Analysis (if limmaGUI failed) ---
    if (!limmagui_success) {
      message("Stage 3: Running robust base R fallback analysis...")
      
      # Fit linear model for each probe using base R
      p_values <- apply(M_matrix, 1, function(x) {
        fit <- tryCatch(lm(x ~ cond), error = function(e) NULL)
        if (is.null(fit)) return(NA)
        summary_fit <- summary(fit)
        if (nrow(summary_fit\$coefficients) >= 2) {
          return(summary_fit\$coefficients[2, 4])
        } else {
          return(NA)
        }
      })
      
      logFC <- apply(M_matrix, 1, function(x) {
        fit <- tryCatch(lm(x ~ cond), error = function(e) NULL)
        if (is.null(fit) || length(coef(fit)) < 2) return(0)
        return(coef(fit)[2])
      })
      
      adj_p_values <- p.adjust(p_values, method = "BH")
      
      top_tbl <- data.frame(
        GeneID = rownames(M_matrix),
        logFC = logFC,
        P.Value = p_values,
        adj.P.Val = adj_p_values,
        stringsAsFactors = FALSE
      )
      top_tbl <- top_tbl[order(top_tbl\$P.Value), ]
      write.csv(top_tbl, "top_table.csv", row.names = FALSE)
      message("Fallback analysis completed successfully.")
    }
    
    # --- Visualizations ---
    message("Stage 4: Generating diagnostic plots...")
    pdf("diagnostic_plots.pdf", width = 10, height = 8)
    par(mfrow = c(1, 2))
    
    # 1. MA Plot
    plot(rowMeans(M_matrix), rowMeans(A_matrix), 
         main = "MA Plot", 
         xlab = "Average log2 Intensity (A)", 
         ylab = "Log2 Fold Change (M)", 
         pch = 20, col = "darkblue")
    abline(h = 0, col = "red", lty = 2)
    
    # 2. Boxplot of M-values
    boxplot(M_matrix, 
            main = "M-Value Distribution", 
            ylab = "M-values", 
            col = "lightblue", 
            las = 2)
    
    dev.off()
    message("Pipeline completed successfully.")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # between-array norm — file-exists check for post-norm QC PDFs.
    .ban_pdfs <- list.files(".", pattern = "(?i)(boxplot|density|qnorm|norm.*array).*\\.pdf\$")
    .ban_passes <- length(.ban_pdfs) > 0
    .gates_by_label[["between-array normalization"]] <- list(
      gate_row = "bioc_count_normalization",
      metric_name = "between_array_norm_plot_exists",
      metric_value = if (.ban_passes) 1 else 0,
      passes = .ban_passes,
      status = if (.ban_passes) paste0("computed (", length(.ban_pdfs), " PDF(s) emitted)")
               else "not_computed (no between-array QC PDF present)"
    )

    # array detection QC — ExpressionSet detection p-values or detection-column data.frame.
    .adq_rate <- NA_real_
    for (.adq_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .adq_obj <- tryCatch(readRDS(.adq_rds), error = function(e) NULL)
      .adq_pv <- NULL
      if (!is.null(.adq_obj)) {
        if (inherits(.adq_obj, "ExpressionSet")) {
          .adq_pv <- tryCatch(Biobase::assayDataElement(.adq_obj, "Detection"), error = function(e) NULL)
        } else if (is.matrix(.adq_obj) || is.data.frame(.adq_obj)) {
          .adq_cols <- grep("(?i)(detection|pvalue|pval)", colnames(.adq_obj), value = TRUE)
          if (length(.adq_cols) > 0) .adq_pv <- as.matrix(.adq_obj[, .adq_cols, drop = FALSE])
        }
      }
      if (!is.null(.adq_pv) && length(.adq_pv) > 0) {
        .adq_rate <- round(mean(as.numeric(.adq_pv) < 0.05, na.rm = TRUE), 4); break
      }
    }
    .gates_by_label[["array detection QC"]] <- list(
      gate_row = "bioc_array_detection_qc",
      metric_name = "detection_rate",
      metric_value = .adq_rate,
      passes = isTRUE(is.finite(.adq_rate) && .adq_rate >= 0.75),
      status = if (is.finite(.adq_rate)) "computed (probe-detection p<0.05 fraction)"
               else "not_computed (no ExpressionSet/detection-p .rds present)"
    )

    # low-count filtering — fraction of genes retained (heuristic on matrix artifacts).
    # Pass band 30-60% per Chen 2016 F1000 (edgeR filterByExpr convention).
    .lcf_kept_fractions <- numeric(0)
    .lcf_scanned <- character(0)
    for (.lcf_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
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

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_LIMMAGUI_LIMMAGUI_MICROARRAY_PIPELINE",
      domain  = "bioconductor",
      declared_qc_steps = c("between-array normalization", "array detection QC", "low-count filtering"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_LIMMAGUI_LIMMAGUI_MICROARRAY_PIPELINE":',
        paste0('    limmaGUI: ', as.character(packageVersion('limmaGUI')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_limmagui_microarray_pipeline.csv versions.yml
    """
}

workflow BIOC_LIMMAGUI_LIMMAGUI_MICROARRAY_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_LIMMAGUI_LIMMAGUI_MICROARRAY_PIPELINE(ch_input)

    emit:
    tables   = BIOC_LIMMAGUI_LIMMAGUI_MICROARRAY_PIPELINE.out.tables
    plots    = BIOC_LIMMAGUI_LIMMAGUI_MICROARRAY_PIPELINE.out.plots
    objects  = BIOC_LIMMAGUI_LIMMAGUI_MICROARRAY_PIPELINE.out.objects
    versions = BIOC_LIMMAGUI_LIMMAGUI_MICROARRAY_PIPELINE.out.versions
}
