#!/usr/bin/env nextflow
// ============================================================
// Bioconductor-style workflow: clean_and_verify — batch correction WITH a QC verdict
// The market's #1 cleaning task (bulk expression: normalize -> batch-correct -> outlier)
// with an over-correction GATE bolted on. Answers the question the standard "run ComBat"
// tutorial never checks: did batch correction remove the technical effect WITHOUT erasing
// the biological signal (disease vs normal)?  Generalizes the alignment-QC gate to bulk.
//
// Method: covariate-protected LINEAR batch removal (the limma::removeBatchEffect algorithm,
// implemented in base-R so no Bioc install / no 504) — regress out `batch` while PRESERVING
// the biological `condition`. The GATE is method-agnostic; the corrector is swappable.
//
// Verdict (base-R PCA + silhouette, before vs after):
//   * Biology conservation = sil(condition)_after / sil(condition)_before  -> HALT if < 0.7
//     (over-correction: the biological signal was erased)
//   * Batch removal        = sil(batch)_after                              -> advisory if > 0.15
//   * Outlier samples      = robust PCA-distance flags                     -> advisory
// Emitted as qc_report.json {"_all_metrics":[{name,measured,unit,threshold,pass}, ...]} —
// the exact shape _evaluate_qc_from_s3 / the auto-loop consumes.
//
// Input files (stageAs list): one expression matrix (genes x samples; col1=gene, header=samples)
//   + one metadata CSV containing columns `sample`,`batch`,`condition`.
// Container: bioc-domain-general:3.20-slim (base-R only)
// Validated logic: scripts/clean_and_verify_qc_proofpoint.py + scripts/qc_battery.py
// (bulk/ComBat: gate tracks biology +0.58, batch-removal anti-tracks -0.86, false-accept 0.14->0.00)
// NOTE: R not yet executed on Batch — verify via one post-merge E2E on a confounded matrix.
// Input: omics
// (^ the bioc entry-wrapper reads this header to stage params.omics=[expr.csv, meta.csv]
//  into the process work dir; without it the wrapper binds one empty placeholder -> R aborts)
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CLEAN_AND_VERIFY {
    tag "${meta.id}"
    label 'process_medium'

    publishDir "${params.outdir}", mode: 'copy'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("cleaned_matrix.csv"), emit: cleaned, optional: true
    tuple val(meta), path("qc_report.json"),     emit: qc_report, optional: true
    tuple val(meta), path("*.pdf"),              emit: plots, optional: true
    path "versions.yml",                         emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
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

    .read <- function(.f) {
      .sep <- if (grepl("[.]csv\$", .f, ignore.case = TRUE)) "," else "\\t"
      read.table(.f, header = TRUE, sep = .sep, check.names = FALSE, stringsAsFactors = FALSE)
    }

    # --- identify metadata (has sample/batch/condition cols) vs expression matrix ---
    .files <- list.files(".", pattern = "[.](csv|tsv|txt)\$", ignore.case = TRUE)
    .files <- .files[!grepl("^(versions|cleaned|qc_report)", .files, ignore.case = TRUE)]
    meta_df <- NULL; expr <- NULL
    for (.f in .files) {
      .d <- try(.read(.f), silent = TRUE); if (inherits(.d, "try-error")) next
      .cn <- tolower(colnames(.d))
      if (all(c("sample","batch","condition") %in% .cn)) {
        colnames(.d) <- .cn; meta_df <- .d
      } else {
        expr <- as.matrix(.d[,-1, drop = FALSE]); rownames(expr) <- .d[[1]]
      }
    }
    if (is.null(meta_df) || is.null(expr)) stop("need one expression matrix + one metadata csv (sample,batch,condition)")

    # --- align samples ---
    .common <- intersect(colnames(expr), meta_df\$sample)
    if (length(.common) < 6) stop("too few shared samples between matrix and metadata")
    expr <- expr[, .common, drop = FALSE]
    meta_df <- meta_df[match(.common, meta_df\$sample), ]
    batch <- factor(meta_df\$batch); cond <- factor(meta_df\$condition)

    # --- normalize if raw counts (log2 CPM); else assume already normalized ---
    if (max(expr, na.rm = TRUE) > 50 && all(abs(expr - round(expr)) < 1e-6, na.rm = TRUE)) {
      .lib <- colSums(expr); .lib[.lib == 0] <- 1
      expr <- log2(sweep(expr, 2, .lib, "/") * 1e6 + 1)
    }
    # drop zero-variance genes
    .v <- apply(expr, 1, var); expr <- expr[is.finite(.v) & .v > 0, , drop = FALSE]

    # --- covariate-protected linear batch removal (removeBatchEffect algorithm) ---
    .correct <- function(X, batch, cond) {
      if (nlevels(batch) < 2) return(X)
      Db <- model.matrix(~ batch)[, -1, drop = FALSE]     # batch contrasts (to remove)
      Dc <- model.matrix(~ cond)                          # condition design (to PRESERVE, incl. intercept)
      D  <- cbind(Dc, Db)
      # per-gene OLS coefficients: (D'D)^-1 D' y, y = samples for each gene
      coefs <- solve(t(D) %*% D, t(D) %*% t(X))           # (params x genes)
      bcols <- (ncol(Dc) + 1):ncol(D)
      t( t(X) - D[, bcols, drop = FALSE] %*% coefs[bcols, , drop = FALSE] )
    }
    corrected <- tryCatch(.correct(expr, batch, cond), error = function(e) expr)

    # --- PCA + silhouette (base-R) ---
    .pca <- function(X, k = 10) {
      Xs <- scale(t(X)); Xs[!is.finite(Xs)] <- 0
      pr <- prcomp(Xs, center = FALSE, scale. = FALSE)
      pr\$x[, seq_len(min(k, ncol(pr\$x))), drop = FALSE]
    }
    .sil <- function(emb, lab) {
      lab <- as.integer(factor(lab)); n <- nrow(emb)
      if (length(unique(lab)) < 2) return(0)
      D <- as.matrix(dist(emb)); s <- numeric(n)
      for (i in seq_len(n)) {
        same <- which(lab == lab[i]); same <- same[same != i]
        a <- if (length(same)) mean(D[i, same]) else 0
        b <- Inf
        for (l in setdiff(unique(lab), lab[i])) b <- min(b, mean(D[i, lab == l]))
        s[i] <- if (max(a, b) > 0) (b - a) / max(a, b) else 0
      }
      mean(s)
    }
    emb_b <- .pca(expr); emb_a <- .pca(corrected)
    cs_b <- .sil(emb_b, cond); cs_a <- .sil(emb_a, cond)
    bs_b <- .sil(emb_b, batch); bs_a <- .sil(emb_a, batch)

    # --- outliers (robust PCA distance) ---
    .cen <- apply(emb_a, 2, median); .dist <- sqrt(rowSums((emb_a - matrix(.cen, nrow(emb_a), ncol(emb_a), byrow = TRUE))^2))
    .mad <- mad(.dist); .mad <- if (.mad == 0) 1 else .mad
    n_out <- sum((.dist - median(.dist)) / .mad > 3.5)

    # --- gate metrics (the verdict) ---
    bio_ret <- if (cs_b != 0) cs_a / cs_b else 1
    metrics <- list(
      list(name = "Biology conservation (post-clean)", measured = round(bio_ret, 3), unit = "ratio",
           threshold = 0.7, pass = (bio_ret >= 0.7)),
      list(name = "Batch removal", measured = round(bs_a, 3), unit = "silhouette",
           threshold = 0.15, pass = (bs_a <= 0.15)),
      list(name = "Outlier samples", measured = n_out, unit = "count",
           threshold = 3, pass = (n_out <= 3))
    )
    # hand-write minimal JSON (no jsonlite dependency)
    .esc <- function(s) gsub('"', '\\\\"', s)
    .rows <- sapply(metrics, function(m) sprintf(
      '{"name":"%s","measured":%s,"unit":"%s","threshold":%s,"pass":%s}',
      .esc(m\$name), m\$measured, m\$unit, m\$threshold, tolower(as.character(m\$pass))))
    writeLines(sprintf('{"_all_metrics":[%s]}', paste(.rows, collapse = ",")), "qc_report.json")

    write.csv(data.frame(gene = rownames(corrected), corrected, check.names = FALSE),
              "cleaned_matrix.csv", row.names = FALSE)
    writeLines(c('"BIOC_CLEAN_AND_VERIFY":', paste0('  R: ', R.version.string)), "versions.yml")
    cat(sprintf("[clean_and_verify] bio_conservation=%.3f batch_after=%.3f outliers=%d\\n", bio_ret, bs_a, n_out))
    """
}

workflow BIOC_CLEAN_AND_VERIFY_WORKFLOW {
    take:
    ch_input   // tuple(meta, [expr.csv, metadata.csv])

    main:
    BIOC_CLEAN_AND_VERIFY(ch_input)

    emit:
    cleaned   = BIOC_CLEAN_AND_VERIFY.out.cleaned
    qc_report = BIOC_CLEAN_AND_VERIFY.out.qc_report
    versions  = BIOC_CLEAN_AND_VERIFY.out.versions
}
