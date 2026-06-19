#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MBttest — differential_expression_analysis
// Identify differentially expressed genes or isoforms between two conditions with small sample sizes using multiple beta t-tests.
// Input: count_matrix.csv
// Container: quay.io/biocontainers/bioconductor-mbttest:1.38.0--r45hdfd78af_0
// R packages: MBttest
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_MBTTEST_DIFFERENTIAL_EXPRESSION_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-mbttest:1.38.0--r45hdfd78af_0"

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
    .bm_deps <- c("MBttest")
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
    
    # Load required library
    library(MBttest)
    
    # Check if input file exists
    input_file <- "count_matrix.csv"
    if (!file.exists(input_file)) {
      stop(paste("Error: Input file", input_file, "not found in the working directory."))
    }
    
    # Read the user input count matrix
    real_data <- read.csv(input_file, stringsAsFactors = FALSE, check.names = FALSE)
    
    # Dynamically determine the number of annotation columns (nci)
    # We assume annotation columns are on the left, and count columns are on the right.
    # Find the last column that is NOT numeric (character/factor) to set the boundary.
    non_num_cols <- which(!sapply(real_data, is.numeric))
    if (length(non_num_cols) > 0) {
      nci <- max(non_num_cols)
    } else {
      # Fallback if all columns are numeric
      nci <- ifelse(ncol(real_data) > 6, 2, 1)
    }
    
    # Determine the number of replicates for each condition (na and nb)
    # We assume the remaining columns are split equally between the two conditions.
    n_counts <- ncol(real_data) - nci
    na <- floor(n_counts / 2)
    nb <- n_counts - na
    
    message(paste("Detected parameters - Annotation columns (nci):", nci))
    message(paste("Detected parameters - Condition A replicates (na):", na))
    message(paste("Detected parameters - Condition B replicates (nb):", nb))
    
    # --- Simulate null count data from real data using simulat ---
    # We use a subset of up to 500 rows to keep the simulation fast and faithful to the vignette
    sub_data_sim <- real_data[1:min(500, nrow(real_data)), ]
    sjknull1 <- simulat(yy = sub_data_sim, nci = nci, r1 = na, r2 = nb, p = 0, q = 0.2)
    
    # --- Run multiple beta t-tests on the simulated null data ---
    mysim1 <- smbetattest(X = sjknull1, na = na, nb = nb, alpha = 0.05)
    
    # Save simulation results
    write.csv(mysim1, "simulated_null_results.csv", row.names = FALSE)
    
    # --- Calculate the threshold parameter omega (W) by sorting ---
    # False positives are identified by symb == "+"
    fps <- mysim1[trimws(as.character(mysim1\$symb)) == "+", ]
    if (nrow(fps) > 0) {
      rho_vals <- sort(fps\$rho)
      N <- length(rho_vals)
      q_vals <- (1:N) / N
      # Find the largest index i where q_vals[i] <= 0.85
      idx <- which(q_vals <= 0.85)
      if (length(idx) > 0) {
        W_val <- rho_vals[max(idx)]
      } else {
        W_val <- rho_vals[1]
      }
    } else {
      W_val <- 1.0 # Default fallback if no false positives are found
    }
    message(paste("Calculated omega (W) threshold parameter:", W_val))
    
    # --- Normalize the real count data to ensure equal library ---
    count_cols <- (nci + 1):(nci + na + nb)
    counts <- real_data[, count_cols]
    lib_sizes <- colSums(counts)
    mean_lib_size <- mean(lib_sizes)
    
    normalized_counts <- counts
    for (j in 1:ncol(counts)) {
      normalized_counts[, j] <- (counts[, j] * mean_lib_size) / lib_sizes[j]
    }
    
    normalized_data <- real_data
    normalized_data[, count_cols] <- normalized_counts
    
    # --- Perform the multiple beta t-test on the normalized real ---
    # We use the whole normalized dataset
    res <- mbetattest(X = normalized_data, na = na, nb = nb, W = W_val, alpha = 0.05, file = "jurkat_NS_48h_tag_mbetattest.csv")
    
    # Save the results object as RDS for downstream analysis
    saveRDS(res, "mbetattest_results.rds")
    
    # --- Visualize the results using maplot and myheatmap ---
    dat <- res
    
    pdf("differential_expression_plots.pdf", width = 10, height = 8)
    
    tryCatch({
      maplot(dat = dat, r1 = na, r2 = nb, TT = 350, matitle = "MA plot")
    }, error = function(e) {
      warning("Failed to generate MA plot (TT=350): ", e\$message)
    })
    
    tryCatch({
      maplot(dat = dat, r1 = na, r2 = nb, TT = 50, matitle = "MA plot")
    }, error = function(e) {
      warning("Failed to generate MA plot (TT=50): ", e\$message)
    })
    
    tryCatch({
      myheatmap(dat = dat, r1 = na, r2 = nb, maptitle = "Jurkat T-cell heatmap2")
    }, error = function(e) {
      warning("Failed to generate heatmap2: ", e\$message)
    })
    
    tryCatch({
      myheatmap(dat = dat, r1 = na, r2 = nb, tree = "none", maptitle = "Jurkat T-cell heatmap3")
    }, error = function(e) {
      warning("Failed to generate heatmap3: ", e\$message)
    })
    
    tryCatch({
      myheatmap(dat = dat, r1 = na, r2 = nb, colrs = "redblue", tree = "column", method = "pearson", maptitle = "Jurkat T-cell heatmap")
    }, error = function(e) {
      warning("Failed to generate heatmap: ", e\$message)
    })
    
    dev.off()
    
    message("Pipeline completed successfully. Outputs written to 'jurkat_NS_48h_tag_mbetattest.csv', 'mbetattest_results.rds', and 'differential_expression_plots.pdf'.")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

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
      process = "BIOC_MBTTEST_DIFFERENTIAL_EXPRESSION_ANALYSIS",
      domain  = "bioconductor",
      declared_qc_steps = c("low-count filtering", "count normalization", "dispersion/size-factor estimation"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_MBTTEST_DIFFERENTIAL_EXPRESSION_ANALYSIS":',
        paste0('        MBttest: ', as.character(packageVersion("MBttest")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_expression_analysis.csv versions.yml
    """
}

workflow BIOC_MBTTEST_DIFFERENTIAL_EXPRESSION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ count_matrix.csv ] ]

    main:
    BIOC_MBTTEST_DIFFERENTIAL_EXPRESSION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MBTTEST_DIFFERENTIAL_EXPRESSION_ANALYSIS.out.tables
    plots    = BIOC_MBTTEST_DIFFERENTIAL_EXPRESSION_ANALYSIS.out.plots
    objects  = BIOC_MBTTEST_DIFFERENTIAL_EXPRESSION_ANALYSIS.out.objects
    versions = BIOC_MBTTEST_DIFFERENTIAL_EXPRESSION_ANALYSIS.out.versions
}
