#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: derfinderHelper — derfinder_helper_fstats
// Calculate genome-wide F-statistics and p-values comparing nested models for RNA-seq count data using derfinderHelper to accelerate the computation.
// Input: counts.csv, coldata.csv
// Container: 1.44.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: IRanges, S4Vectors, derfinderHelper
// Visualizations: plot (ggplot/base)
// QC: low-count filtering
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DERFINDERHELPER_DERFINDER_HELPER_FSTATS {
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
    .bm_deps <- c("S4Vectors", "derfinderHelper")
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
    
    # --- Load required libraries ---
    suppressPackageStartupMessages({
        library(S4Vectors)
        library(derfinderHelper)
    })
    
    # --- Read and preprocess input data ---
    if (!file.exists("counts.csv") || !file.exists("coldata.csv")) {
        stop("Required input files 'counts.csv' and/or 'coldata.csv' are missing.")
    }
    
    counts <- read.csv("counts.csv", row.names = 1, check.names = FALSE)
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    # Ensure sample alignment between counts and metadata
    common_samples <- intersect(coldata\$sample, colnames(counts))
    if (length(common_samples) == 0) {
        stop("No matching samples found between 'counts.csv' and 'coldata.csv'.")
    }
    
    counts <- counts[, common_samples, drop = FALSE]
    coldata <- coldata[match(common_samples, coldata\$sample), , drop = FALSE]
    
    # Filter out low-expression genes to improve statistical power
    keep <- rowSums(counts > 5) >= (ncol(counts) / 2)
    counts_filtered <- counts[keep, , drop = FALSE]
    
    if (nrow(counts_filtered) == 0) {
        warning("No genes passed the filtering criteria. Proceeding with unfiltered data.")
        counts_filtered <- counts
    }
    
    # --- Prepare data structure for derfinderHelper ---
    # derfinderHelper expects a DataFrame of Rle objects for memory efficiency
    rle_list <- lapply(seq_len(ncol(counts_filtered)), function(i) {
        Rle(as.numeric(counts_filtered[[i]]))
    })
    names(rle_list) <- colnames(counts_filtered)
    toyData <- DataFrame(rle_list)
    
    # --- Build nested model matrices ---
    # We adjust for sample depth (library size) as a covariate
    sampleDepth <- colSums(counts_filtered)
    condition <- factor(coldata\$condition)
    
    # Alternative model (includes condition of interest)
    mod <- model.matrix(~ sampleDepth + condition)
    # Null model (nested, excludes condition of interest)
    mod0 <- model.matrix(~ sampleDepth)
    
    # --- Calculate F-statistics using derfinderHelper ---
    # Using 'Matrix' method as recommended for optimal speed and memory usage
    fstats_rle <- fstats.apply(
        data = toyData, 
        mod = mod, 
        mod0 = mod0, 
        scalefac = 1, 
        method = "Matrix"
    )
    
    # Convert Run-Length Encoded (Rle) F-statistics back to numeric vector
    f_values <- as.numeric(fstats_rle)
    
    # --- Compute statistical significance (p-values) ---
    df1 <- ncol(mod) - ncol(mod0)
    df2 <- nrow(mod) - ncol(mod)
    
    p_values <- pf(f_values, df1, df2, lower.tail = FALSE)
    adj_p_values <- p.adjust(p_values, method = "BH")
    
    # --- Export results and diagnostic plots ---
    results <- data.frame(
        gene_id = rownames(counts_filtered),
        f_statistic = f_values,
        p_value = p_values,
        adj_p_value = adj_p_values,
        stringsAsFactors = FALSE
    )
    
    write.csv(results, "fstats_results.csv", row.names = FALSE)
    
    # Generate diagnostic plot
    pdf("fstats_distribution.pdf", width = 7, height = 5)
    hist(
        p_values, 
        breaks = 50, 
        col = "skyblue", 
        border = "white",
        main = "P-value Distribution (F-test)", 
        xlab = "p-value",
        ylab = "Frequency"
    )
    dev.off()
    
    cat("Analysis complete. Results written to 'fstats_results.csv' and 'fstats_distribution.pdf'.\n")
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

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_DERFINDERHELPER_DERFINDER_HELPER_FSTATS",
      domain  = "bioconductor",
      declared_qc_steps = c("low-count filtering"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_DERFINDERHELPER_DERFINDER_HELPER_FSTATS":',
        paste0('    derfinderHelper: ', as.character(packageVersion('derfinderHelper')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_derfinder_helper_fstats.csv versions.yml
    """
}

workflow BIOC_DERFINDERHELPER_DERFINDER_HELPER_FSTATS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_DERFINDERHELPER_DERFINDER_HELPER_FSTATS(ch_input)

    emit:
    tables   = BIOC_DERFINDERHELPER_DERFINDER_HELPER_FSTATS.out.tables
    plots    = BIOC_DERFINDERHELPER_DERFINDER_HELPER_FSTATS.out.plots
    objects  = BIOC_DERFINDERHELPER_DERFINDER_HELPER_FSTATS.out.objects
    versions = BIOC_DERFINDERHELPER_DERFINDER_HELPER_FSTATS.out.versions
}
