#!/usr/bin/env nextflow
// ============================================================
// Bioconductor-style workflow: JIVE — Joint and Individual Variation Explained
// JIVE (Lock et al. 2013) decomposes a multi-omics dataset into a low-rank JOINT
// structure shared across all layers plus layer-INDIVIDUAL structure. One of the
// variance-decomposition methods benchmarked in Cantini et al. 2021. Samples are then
// clustered on an embedding built from the joint structure. Part of the BioMate
// multi-omics SOTA method set — same universal CSV input contract as MOFA2/SNF/intNMF,
// standardized clusters.csv output.
// Input: omics
// Container: bioc-domain-general:3.20-slim (r.jive from CRAN at runtime)
// R packages: r.jive
// ============================================================

nextflow.enable.dsl = 2

process BIOC_JIVE_MULTIOMICS {
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
    # r.jive is CRAN — install as a fast p3m.dev noble binary (no Bioc mirror, no 504).
    if (!requireNamespace("r.jive", quietly = TRUE)) install.packages("r.jive", Ncpus = 2)

    # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
    for (.bm_d in list.files(".", full.names = TRUE)) {
      if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
        for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
          if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
        }
      }
    }

    suppressMessages({ library(r.jive) })

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
    # differ per omic). JIVE requires the shared (sample) dimension identical across views.
    .common <- Reduce(intersect, lapply(data, colnames))
    stopifnot(length(.common) >= 2)
    data <- lapply(data, function(m) m[, .common, drop = FALSE])
    cat(sprintf("[jive] %d views aligned to %d common samples\\n", length(data), length(.common)))

    # --- JIVE data prep: features x samples (as-is); impute NAs; cap features for speed ---
    K <- ${params.n_clusters ?: 4}L   # clusters; pass n_clusters to match the label's
                                       # class count for fair cross-method comparison
    dat <- lapply(data, function(m) {
      M <- as.matrix(m); storage.mode(M) <- "double"    # features x samples
      for (i in seq_len(nrow(M))) {                      # impute NA by feature (row) mean
        v <- M[i, ]; if (any(is.na(v))) { mu <- mean(v, na.rm = TRUE); v[is.na(v)] <- if (is.finite(mu)) mu else 0; M[i, ] <- v }
      }
      if (nrow(M) > 2000) {                              # cap to top-2000 variable features (tractable SVD)
        vars <- apply(M, 1, var)
        M <- M[order(vars, decreasing = TRUE)[1:2000], , drop = FALSE]
      }
      M
    })

    # --- JIVE decomposition with given ranks (avoids slow permutation rank-selection) ---
    set.seed(1)
    rankA <- rep(2L, length(dat))
    res <- r.jive::jive(dat, rankJ = K, rankA = rankA, method = "given",
                        scale = TRUE, center = TRUE, maxiter = 100, showProgress = FALSE)

    # sample embedding from the JOINT structure: res\$joint is a list (one features x
    # samples matrix per view, shared sample columns). Row-bind -> SVD -> right singular
    # vectors (\$v) are the samples x components joint embedding.
    J <- if (is.list(res\$joint)) do.call(rbind, res\$joint) else as.matrix(res\$joint)
    nv <- max(1L, min(K, ncol(J) - 1L, nrow(J)))
    emb <- svd(J, nu = 0, nv = nv)\$v                     # samples x nv
    group <- kmeans(emb, centers = K, nstart = 10)\$cluster
    samples <- colnames(data[[1]])

    write.csv(data.frame(sample = samples, cluster = as.integer(group), check.names = FALSE),
              "jive_clusters.csv", row.names = FALSE)
    write.csv(data.frame(view = names(data), n_features = vapply(dat, nrow, 0L), check.names = FALSE),
              "jive_views.csv", row.names = FALSE)

    writeLines(c('"BIOC_JIVE_MULTIOMICS":',
      paste0('    r.jive: ', as.character(packageVersion('r.jive')))), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch jive_clusters.csv versions.yml
    """
}

workflow BIOC_JIVE_MULTIOMICS_WORKFLOW {
    take:
    ch_input   // channel: [ val(meta), [ omics matrices ] ]

    main:
    BIOC_JIVE_MULTIOMICS(ch_input)

    emit:
    tables   = BIOC_JIVE_MULTIOMICS.out.tables
    versions = BIOC_JIVE_MULTIOMICS.out.versions
}
