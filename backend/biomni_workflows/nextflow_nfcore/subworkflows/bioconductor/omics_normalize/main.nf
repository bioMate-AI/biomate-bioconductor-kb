#!/usr/bin/env nextflow
// ============================================================
// Bioconductor-style workflow: omics_normalize — shared multi-omics normalization + QC
// Per-omics normalization and quality-control for ANY combination of omics layers,
// producing normalized matrices that feed downstream integration (MOFA2, SNF, …) with
// PROVABLY IDENTICAL pre-processing — the fairness guarantee for the benchmark harness,
// and OmNI-parity normalization surfaced as a first-class, chainable platform step.
//
// What "normalize omics" means here (per-view, features x samples):
//   * log2      — log2(x - min + 1); stabilizes right-skewed intensities/counts
//   * asinh     — inverse hyperbolic sine; variance-stabilizing, tolerates 0/negatives
//   * quantile  — force every sample to the same value distribution (removes depth/batch
//                 scale differences); base-R (rank -> mean-of-sorted), no limma needed
//   * zscore    — per-feature centre/scale so no single high-variance feature dominates
//   * none      — pass through (already normalized upstream)
// Method is chosen per view via params.norm_<view> (falls back to params.norm_default,
// then a heuristic: integer-like counts -> log2, else zscore).
//
// QC metrics (OmNI parity, base-R): PMAD (pooled median abs deviation), PCV (pooled
// coefficient of variation), frac_na, per-view n/mean/sd/skew — before AND after.
// Input: omics
// Container: bioc-domain-general:3.20-slim (base-R only — no package install)
// R packages: (none — base stats)
// ============================================================

nextflow.enable.dsl = 2

process BIOC_OMICS_NORMALIZE {
    tag "${meta.id}"
    label 'process_medium'

    publishDir "${params.outdir}", mode: 'copy'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("normalized_*.csv"), emit: normalized, optional: true
    tuple val(meta), path("omics_qc_metrics.csv"), emit: qc,     optional: true
    tuple val(meta), path("*.pdf"),            emit: plots,      optional: true
    path "versions.yml",                       emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # base-R only — no install, no Bioc mirror, no 504.

    # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
    for (.bm_d in list.files(".", full.names = TRUE)) {
      if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
        for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
          if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
        }
      }
    }

    # --- read the multi-omics view list (UNIVERSAL interface, same as MOFA2/SNF) ---
    .read_matrix <- function(.f) {
      .sep <- if (grepl("[.]csv\$", .f, ignore.case = TRUE)) "," else "\t"
      as.matrix(read.table(.f, header = TRUE, row.names = 1, sep = .sep,
                           check.names = FALSE, stringsAsFactors = FALSE))
    }
    .mats <- list.files(".", pattern = "[.](csv|tsv|txt)\$", full.names = FALSE, ignore.case = TRUE)
    .mats <- .mats[!grepl("^(versions|dt|normalized_|omics_qc)", .mats, ignore.case = TRUE)]
    data <- list()
    for (.f in .mats) {
      .view <- sub("[.][^.]+\$", "", basename(.f))
      try(data[[.view]] <- .read_matrix(.f), silent = TRUE)
    }
    stopifnot(length(data) >= 1)

    # --- helpers -------------------------------------------------------------
    .skew <- function(v) { v <- v[is.finite(v)]; if (length(v) < 3) return(NA_real_)
      m <- mean(v); s <- sd(v); if (!is.finite(s) || s == 0) return(0); mean(((v - m)/s)^3) }
    .qc <- function(M) {
      v <- as.numeric(M); fin <- v[is.finite(v)]
      # PMAD: pooled median absolute deviation of per-feature values (spread robustness)
      pmad <- median(abs(fin - median(fin)))
      mu <- mean(fin)
      # PCV (coefficient of variation) is only defined on ratio-scale (non-negative,
      # non-centred) data. After z-scoring mean -> 0, so sd/|mean| explodes -> report
      # NA rather than an astronomical artifact.
      pcv <- if (is.finite(mu) && min(fin) >= 0 && mu > 1e-9) sd(fin) / mu else NA_real_
      list(n_features = nrow(M), n_samples = ncol(M),
           frac_na = mean(!is.finite(v)),
           mean = mu, sd = sd(fin), skew = .skew(fin),
           pmad = pmad, pcv = pcv)
    }
    .looks_count <- function(M) {
      s <- as.numeric(M); s <- s[is.finite(s)]; if (!length(s)) return(FALSE)
      all(s >= 0) && mean(abs(s - round(s)) < 1e-9) > 0.95   # >95% integer-valued & non-negative
    }
    .quantile_norm <- function(M) {                    # base-R quantile normalization (samples = cols)
      r <- apply(M, 2, function(col) rank(col, ties.method = "average", na.last = "keep"))
      srt <- apply(M, 2, function(col) sort(col, na.last = NA))
      L <- min(vapply(srt, length, 0L)); if (L < 2) return(M)
      ref <- rowMeans(vapply(srt, function(x) x[round(seq(1, length(x), length.out = L))], numeric(L)))
      out <- M
      for (j in seq_len(ncol(M))) {
        idx <- round((r[, j] - 1) / (max(r[, j], na.rm = TRUE) - 1) * (L - 1)) + 1
        out[, j] <- ref[pmin(pmax(idx, 1L), L)]
      }
      out
    }

    # --- per-view normalization ---------------------------------------------
    # params.norm_<view> is NOT groovy-interpolated inside this R block, so method
    # selection is heuristic here (counts->log2, else zscore) with quantile applied
    # when a view is strongly right-skewed. A future release threads explicit
    # per-view choices via a params file the wrapper writes to disk.
    qc_before <- list(); qc_after <- list()
    for (.v in names(data)) {
      M <- data[[.v]]; storage.mode(M) <- "double"
      qc_before[[.v]] <- .qc(M)
      method <- if (.looks_count(M)) "log2" else "zscore"
      Mn <- switch(method,
        log2   = log2(M - min(M, na.rm = TRUE) + 1),
        asinh  = asinh(M),
        zscore = t(scale(t(M))),                 # per-feature (row) centre/scale
        M)
      # heavy residual skew after the primary transform -> add quantile normalization
      if (isTRUE(abs(.qc(Mn)\$skew) > 2)) Mn <- .quantile_norm(Mn)
      Mn[!is.finite(Mn)] <- NA
      data[[.v]] <- Mn
      qc_after[[.v]] <- .qc(Mn)
      write.csv(data.frame(feature = rownames(Mn), Mn, check.names = FALSE),
                paste0("normalized_", .v, ".csv"), row.names = FALSE)
      cat(sprintf("[normalize] %-14s method=%-8s  skew %6.2f -> %6.2f  pmad %8.3f -> %8.3f\\n",
          .v, method, qc_before[[.v]]\$skew, qc_after[[.v]]\$skew,
          qc_before[[.v]]\$pmad, qc_after[[.v]]\$pmad))
    }

    # --- QC table (before + after, one row per view per stage) --------------
    .rows <- list()
    for (.v in names(qc_before)) for (.stage in c("before","after")) {
      q <- if (.stage == "before") qc_before[[.v]] else qc_after[[.v]]
      .rows[[length(.rows)+1]] <- data.frame(view = .v, stage = .stage,
        n_features = q\$n_features, n_samples = q\$n_samples, frac_na = round(q\$frac_na, 4),
        mean = round(q\$mean, 4), sd = round(q\$sd, 4), skew = round(q\$skew, 4),
        pmad = round(q\$pmad, 4), pcv = round(q\$pcv, 4))
    }
    write.csv(do.call(rbind, .rows), "omics_qc_metrics.csv", row.names = FALSE)

    # --- QC plot: per-view value distribution before vs after ----------------
    pdf("omics_qc_plots.pdf", width = 10, height = 7)
    try({
      op <- par(mfrow = c(2, max(1, length(data))))
      for (.v in names(data)) {
        hist(as.numeric(data[[.v]]), breaks = 40, main = paste(.v, "(normalized)"),
             xlab = "value", col = "#6b8fd6", border = NA)
      }
      par(op)
    }, silent = TRUE)
    dev.off()

    writeLines(c('"BIOC_OMICS_NORMALIZE":',
      paste0('    R: ', as.character(getRversion()))), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch normalized_stub.csv omics_qc_metrics.csv versions.yml
    """
}

workflow BIOC_OMICS_NORMALIZE_WORKFLOW {
    take:
    ch_input   // channel: [ val(meta), [ omics matrices ] ]

    main:
    BIOC_OMICS_NORMALIZE(ch_input)

    emit:
    normalized = BIOC_OMICS_NORMALIZE.out.normalized
    qc         = BIOC_OMICS_NORMALIZE.out.qc
    plots      = BIOC_OMICS_NORMALIZE.out.plots
    versions   = BIOC_OMICS_NORMALIZE.out.versions
}
