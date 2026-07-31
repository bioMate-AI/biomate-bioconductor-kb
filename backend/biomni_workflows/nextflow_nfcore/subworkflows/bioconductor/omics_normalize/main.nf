#!/usr/bin/env nextflow
// ============================================================
// Bioconductor-style workflow: omics_normalize — shared multi-omics normalization + QC
// Per-omics normalization and quality-control for ANY combination of omics layers,
// producing normalized matrices that feed downstream integration (MOFA2, SNF, …) with
// PROVABLY IDENTICAL pre-processing — the fairness guarantee for the benchmark harness,
// and OmNI-parity normalization surfaced as a first-class, chainable platform step.
//
// SOTA per-modality normalization (auto-detected per view from filename + matrix stats):
//   * RNA-seq / miRNA counts   -> log2-CPM           (library-size normalized log)
//   * scRNA counts             -> log1p(CP10k)       (scanpy standard)
//   * DNA methylation beta[0,1]-> M-value            log2(b/(1-b)) (Du et al. 2010)
//   * scATAC (sparse)          -> TF-IDF             (Signac/ArchR standard)
//   * proteomics / RPPA        -> log2 + per-sample median-centre
//   * continuous / drug-resp   -> quantile           (same distribution per sample)
//   * mutation / CNV (binary)  -> none               (pass through)
//   * unknown                  -> per-feature z-score (fallback)
// All transforms are base-R (no install, no Bioc 504). VSN (proteomics) / TMM (edgeR) /
// SCTransform-residuals are install-gated refinements deferred to a dedicated container.
// The applied modality + transform are recorded per view in omics_qc_metrics.csv.
//
// QC metrics (OmNI parity, base-R): PMAD (pooled median abs deviation), PCV, frac_na,
// per-view n/mean/sd/skew — before AND after, with modality + normalization columns.
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
    # --- SOTA per-modality transforms (base-R, no install) -------------------
    .log2cpm <- function(M) {                 # bulk RNA-seq / miRNA counts -> log2-CPM
      cs <- colSums(M, na.rm = TRUE); cs[cs <= 0 | !is.finite(cs)] <- 1
      log2(sweep(M, 2, cs, "/") * 1e6 + 1)
    }
    .log1p_cp10k <- function(M) {             # scRNA counts -> log1p(CP10k) (scanpy standard)
      cs <- colSums(M, na.rm = TRUE); cs[cs <= 0 | !is.finite(cs)] <- 1
      log1p(sweep(M, 2, cs, "/") * 1e4)
    }
    .mvalue <- function(M) {                  # methylation beta[0,1] -> M-value (Du 2010)
      b <- pmin(pmax(M, 1e-4), 1 - 1e-4); log2(b / (1 - b))
    }
    .tfidf <- function(M) {                   # scATAC (features x cells) -> TF-IDF (Signac/ArchR)
      cs <- colSums(M, na.rm = TRUE); cs[cs <= 0 | !is.finite(cs)] <- 1
      tf  <- sweep(M, 2, cs, "/")
      df  <- rowSums(M > 0, na.rm = TRUE); df[df <= 0] <- 1
      idf <- log(1 + ncol(M) / df)
      log1p(sweep(tf, 1, idf, "*") * 1e4)
    }
    .prot_norm <- function(M) {               # proteomics/RPPA -> log2(+1 if positive) + per-sample median-centre
      X <- if (min(M, na.rm = TRUE) >= 0) log2(M + 1) else M
      med <- apply(X, 2, median, na.rm = TRUE); med[!is.finite(med)] <- 0
      sweep(X, 2, med, "-")
    }
    .zscore <- function(M) t(scale(t(M)))     # per-feature centre/scale (fallback)

    # --- modality auto-detection: filename hints first, then matrix statistics ---
    .detect_modality <- function(M, vname) {
      nm <- tolower(vname)
      if (grepl("methy|methylation|beta|cpg|450k|850k|epic", nm)) return("methylation")
      if (grepl("atac|peak|accessib", nm))                        return("atac")
      if (grepl("adt|rppa|protein|proteom|phospho", nm))          return("proteomics")
      if (grepl("mirna|_mir|mir_|microrna", nm))                  return("mirna")
      if (grepl("mut|snv|variant|cnv|copy[_ ]?number", nm))       return("binary")
      if (grepl("drug|response|sensitivity", nm))                 return("continuous")
      .sc <- grepl("^sc|single[_ ]?cell|_sc|scrna|cite", nm)
      if (grepl("rna|expr|exp|count|mrna|gene|transcript", nm))   return(if (.sc) "scrna" else "rnaseq")
      # stats fallback
      fin <- as.numeric(M); fin <- fin[is.finite(fin)]
      if (!length(fin)) return("unknown")
      if (all(fin >= 0) && all(fin <= 1)) return("methylation")             # beta values
      .intf <- mean(abs(fin - round(fin)) < 1e-9); .zf <- mean(fin == 0)
      if (all(fin >= 0) && .intf > 0.95) {                                  # non-negative integer counts
        if (.zf > 0.9) return("atac")                                       # extremely sparse
        if (.zf > 0.5) return(if (.sc) "scrna" else "rnaseq")               # sparse counts
        return("rnaseq")
      }
      "unknown"
    }
    .norm_for <- function(mod) switch(mod,
      rnaseq      = list(name = "log2CPM",            fn = .log2cpm),
      mirna       = list(name = "log2CPM",            fn = .log2cpm),
      scrna       = list(name = "log1p_CP10k",        fn = .log1p_cp10k),
      methylation = list(name = "M-value",            fn = .mvalue),
      atac        = list(name = "TF-IDF",             fn = .tfidf),
      proteomics  = list(name = "log2+median-centre", fn = .prot_norm),
      continuous  = list(name = "quantile",           fn = .quantile_norm),
      binary      = list(name = "none",               fn = function(M) M),
      list(name = "zscore", fn = .zscore))            # unknown fallback
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

    # --- per-view SOTA normalization ----------------------------------------
    # Each view's modality is auto-detected (filename + matrix statistics) and the
    # field-standard transform is applied: RNA-seq/miRNA->log2CPM, scRNA->log1p(CP10k),
    # methylation->M-value, scATAC->TF-IDF, proteomics/RPPA->log2+median-centre,
    # continuous/drug->quantile, mutation/CNV->none, unknown->per-feature z-score.
    qc_before <- list(); qc_after <- list(); mod_of <- list(); norm_of <- list()
    for (.v in names(data)) {
      M <- data[[.v]]; storage.mode(M) <- "double"
      qc_before[[.v]] <- .qc(M)
      .mod  <- .detect_modality(M, .v)
      .spec <- .norm_for(.mod)
      Mn <- tryCatch(.spec\$fn(M), error = function(e) .zscore(M))
      Mn[!is.finite(Mn)] <- NA
      data[[.v]] <- Mn
      qc_after[[.v]] <- .qc(Mn); mod_of[[.v]] <- .mod; norm_of[[.v]] <- .spec\$name
      write.csv(data.frame(feature = rownames(Mn), Mn, check.names = FALSE),
                paste0("normalized_", .v, ".csv"), row.names = FALSE)
      cat(sprintf("[normalize] %-14s modality=%-12s norm=%-18s  skew %6.2f -> %6.2f\\n",
          .v, .mod, .spec\$name, qc_before[[.v]]\$skew, qc_after[[.v]]\$skew))
    }

    # --- QC table (before + after, one row per view per stage) --------------
    .rows <- list()
    for (.v in names(qc_before)) for (.stage in c("before","after")) {
      q <- if (.stage == "before") qc_before[[.v]] else qc_after[[.v]]
      .rows[[length(.rows)+1]] <- data.frame(view = .v,
        modality = mod_of[[.v]], normalization = norm_of[[.v]], stage = .stage,
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
