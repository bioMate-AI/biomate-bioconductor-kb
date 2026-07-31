#!/usr/bin/env nextflow
// ============================================================
// Bioconductor-style workflow: MFA (base-R) — Multiple Factor Analysis multi-omics clustering
// NOTE: replaces RGCCA and the FactoMineR::MFA attempt. BOTH pulled the `Deriv` dependency
// (RGCCA directly; FactoMineR -> car -> pbkrtest -> Deriv), which has no noble binary on p3m
// and fails to compile (`make Error 1`, codegen Makefile) in bioc-domain-general:3.20-slim.
// This implements MFA directly via its ACTUAL algorithm in BASE-R: standardize each block,
// weight each block by 1/(first singular value) so no single block dominates the joint
// variance, concatenate, then a global SVD -> shared sample factor coordinates -> k-means.
// Zero package install (no Deriv, no Bioc 504, no compile). Same multi-block factor family
// as MFA/RGCCA. Process/workflow names kept as *_RGCCA_* so the executor resolves the file
// path unchanged; the METHOD is MFA. Universal CSV interface as MOFA2/SNF.
// Input: omics
// Container: bioc-domain-general:3.20-slim (base-R only — no install)
// R packages: (none — base stats: svd, scale, kmeans)
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RGCCA_MULTIOMICS {
    tag "${meta.id}"
    label 'process_medium'

    publishDir "${params.outdir}", mode: 'copy'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables,  optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # base-R only — MFA via block-weighted global SVD. No install, no Deriv, no Bioc 504.

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
    .mats <- .mats[!grepl("^(versions|dt)[._]", .mats, ignore.case = TRUE)]
    data <- list()
    for (.f in .mats) {
      .view <- sub("[.][^.]+\$", "", basename(.f))
      try(data[[.view]] <- .read_matrix(.f), silent = TRUE)
    }
    stopifnot(length(data) >= 2)

    # [biomate] align all views to their COMMON samples, consistent order (real cohorts
    # differ per omic). MFA requires identical samples/order across blocks.
    .common <- Reduce(intersect, lapply(data, colnames))
    stopifnot(length(.common) >= 2)
    data <- lapply(data, function(m) m[, .common, drop = FALSE])
    cat(sprintf("[mfa] %d views aligned to %d common samples\\n", length(data), length(.common)))

    # --- per-block prep: samples x features, impute NA, drop zero-var, cap, STANDARDIZE ---
    .prep <- function(m) {
      X <- t(as.matrix(m))                      # samples x features
      for (j in seq_len(ncol(X))) {             # impute NAs by feature mean
        v <- X[, j]; if (any(is.na(v))) { mu <- mean(v, na.rm = TRUE); v[is.na(v)] <- if (is.finite(mu)) mu else 0; X[, j] <- v }
      }
      vv <- apply(X, 2, var)
      X <- X[, is.finite(vv) & vv > 0, drop = FALSE]        # drop zero-variance features
      if (ncol(X) > 2000) {                                 # cap to top-2000 most-variable for speed
        vv <- apply(X, 2, var); X <- X[, order(vv, decreasing = TRUE)[1:2000], drop = FALSE]
      }
      X <- scale(X)                                         # standardize each feature (MFA type='s')
      X[!is.finite(X)] <- 0
      X
    }
    blocks <- lapply(data, .prep)

    # --- MFA algorithm (base-R): weight each block by 1/(first singular value) so no block
    #     dominates, concatenate, global SVD -> sample factor coordinates -> k-means. ---
    ncp <- max(2L, ${params.n_clusters ?: 4}L)
    .wblocks <- lapply(blocks, function(X) {
      d1 <- tryCatch(svd(X, nu = 0, nv = 0)\$d[1], error = function(e) 1)
      if (!is.finite(d1) || d1 <= 0) d1 <- 1
      X / d1                                                # MFA block weighting
    })
    M <- do.call(cbind, .wblocks)                           # samples x (weighted) features
    .sv <- svd(M, nu = min(as.integer(ncp), nrow(M) - 1L), nv = 0)
    .k  <- min(as.integer(ncp), ncol(.sv\$u), length(.sv\$d))
    coords <- sweep(.sv\$u[, seq_len(.k), drop = FALSE], 2, .sv\$d[seq_len(.k)], "*")  # samples x factors
    set.seed(1)
    group <- kmeans(coords, ${params.n_clusters ?: 4}, nstart = 10)\$cluster
    samples <- rownames(M); if (is.null(samples)) samples <- .common

    write.csv(data.frame(sample = samples, cluster = as.integer(group), check.names = FALSE),
              "mfa_clusters.csv", row.names = FALSE)
    write.csv(data.frame(view = names(data), n_features = vapply(data, nrow, 0L), check.names = FALSE),
              "mfa_views.csv", row.names = FALSE)

    writeLines(c('"BIOC_RGCCA_MULTIOMICS":',
      paste0('    method: MFA (base-R block-weighted SVD; R ', as.character(getRversion()), ')')),
      "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch mfa_clusters.csv versions.yml
    """
}

workflow BIOC_RGCCA_MULTIOMICS_WORKFLOW {
    take:
    ch_input   // channel: [ val(meta), [ omics matrices ] ]

    main:
    BIOC_RGCCA_MULTIOMICS(ch_input)

    emit:
    tables   = BIOC_RGCCA_MULTIOMICS.out.tables
    versions = BIOC_RGCCA_MULTIOMICS.out.versions
}
