#!/usr/bin/env nextflow
// ============================================================
// Bioconductor-style workflow: RGCCA — regularized generalized CCA multi-omics clustering
// Regularized Generalized Canonical Correlation Analysis (Tenenhaus & Tenenhaus 2011) —
// the canonical-correlation-family representative among the 9 joint-DR methods in
// Cantini et al. 2021. Finds correlated sample factors across all omics blocks, then
// clusters samples on the concatenated block factors. Part of the BioMate multi-omics
// SOTA method set — same universal CSV input contract as MOFA2/SNF/intNMF, standardized
// clusters.csv output.
// Input: omics
// Container: bioc-domain-general:3.20-slim (RGCCA from CRAN at runtime)
// R packages: RGCCA
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
    # RGCCA is CRAN — install as a fast p3m.dev noble binary (no Bioc mirror, no 504).
    if (!requireNamespace("RGCCA", quietly = TRUE)) install.packages("RGCCA", Ncpus = 2)

    # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
    for (.bm_d in list.files(".", full.names = TRUE)) {
      if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
        for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
          if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
        }
      }
    }

    suppressMessages({ library(RGCCA) })

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
    # differ per omic). RGCCA requires identical samples/order across blocks.
    .common <- Reduce(intersect, lapply(data, colnames))
    stopifnot(length(.common) >= 2)
    data <- lapply(data, function(m) m[, .common, drop = FALSE])
    cat(sprintf("[rgcca] %d views aligned to %d common samples\\n", length(data), length(.common)))

    # --- RGCCA data prep: blocks as samples x features, impute NA, cap variable features ---
    .prep <- function(m) {
      X <- t(as.matrix(m))                      # RGCCA expects samples x features (blocks)
      for (j in seq_len(ncol(X))) {             # impute NAs by feature mean (needs complete data)
        v <- X[, j]; if (any(is.na(v))) { mu <- mean(v, na.rm = TRUE); v[is.na(v)] <- if (is.finite(mu)) mu else 0; X[, j] <- v }
      }
      if (ncol(X) > 2000) {                     # cap to top-2000 most-variable features for speed
        vv <- apply(X, 2, var); X <- X[, order(vv, decreasing = TRUE)[1:2000], drop = FALSE]
      }
      X
    }
    blocks <- lapply(data, .prep)

    # --- generalized CCA -> concatenated sample factors -> clustering ---
    set.seed(1)
    res <- RGCCA::rgcca(blocks = blocks, ncomp = 2, scheme = "factorial",
                        scale = TRUE, verbose = FALSE)
    # res\$Y is a list of block sample-score matrices (samples x ncomp); concatenate them
    emb <- if (!is.null(res\$Y)) do.call(cbind, res\$Y) else stop("RGCCA: no sample factors in res\$Y")
    group <- kmeans(emb, ${params.n_clusters ?: 4})\$cluster
    samples <- colnames(data[[1]])

    write.csv(data.frame(sample = samples, cluster = as.integer(group), check.names = FALSE),
              "rgcca_clusters.csv", row.names = FALSE)
    write.csv(data.frame(view = names(data), n_features = vapply(data, nrow, 0L), check.names = FALSE),
              "rgcca_views.csv", row.names = FALSE)

    writeLines(c('"BIOC_RGCCA_MULTIOMICS":',
      paste0('    RGCCA: ', as.character(packageVersion('RGCCA')))), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch rgcca_clusters.csv versions.yml
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
