#!/usr/bin/env nextflow
// ============================================================
// Bioconductor-style workflow: intNMF — integrative NMF multi-omics clustering
// Integrative Non-negative Matrix Factorization (Chalise & Fridley 2017) — the method
// Cantini et al. 2021 found BEST for clustering among 9 joint-DR approaches. Jointly
// factorizes all omics layers into a shared non-negative basis, then clusters samples by
// their dominant basis component. Part of the BioMate multi-omics SOTA method set —
// same universal CSV input contract as MOFA2/SNF, standardized clusters.csv output.
// Input: omics
// Container: bioc-domain-general:3.20-slim (IntNMF from CRAN at runtime)
// R packages: IntNMF
// ============================================================

nextflow.enable.dsl = 2

process BIOC_INTNMF_MULTIOMICS {
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
    # IntNMF is CRAN — install as a fast p3m.dev noble binary (no Bioc mirror, no 504).
    if (!requireNamespace("IntNMF", quietly = TRUE)) install.packages("IntNMF", Ncpus = 2)

    # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
    for (.bm_d in list.files(".", full.names = TRUE)) {
      if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
        for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
          if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
        }
      }
    }

    suppressMessages({ library(IntNMF) })

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
    # differ per omic). IntNMF requires identical samples/order across matrices.
    .common <- Reduce(intersect, lapply(data, colnames))
    stopifnot(length(.common) >= 2)
    data <- lapply(data, function(m) m[, .common, drop = FALSE])
    cat(sprintf("[intnmf] %d views aligned to %d common samples\\n", length(data), length(.common)))

    # --- IntNMF data prep: samples x features, NON-NEGATIVE, scaled to comparable range ---
    K <- 4L   # number of clusters (cancer-subtype default; k-matching to the label's class
              # count is the documented fairness refinement — see foundation roadmap)
    dat <- lapply(data, function(m) {
      X <- t(as.matrix(m))                      # IntNMF expects samples x features
      for (j in seq_len(ncol(X))) {             # impute NAs by feature mean (needs complete data)
        v <- X[, j]; if (any(is.na(v))) { mu <- mean(v, na.rm = TRUE); v[is.na(v)] <- if (is.finite(mu)) mu else 0; X[, j] <- v }
      }
      if (min(X) < 0) X <- X - min(X)           # NMF requires non-negativity
      mx <- max(X); if (mx > 0) X <- X / mx      # scale to [0,1] so views are comparable
      X + .Machine\$double.eps                   # avoid degenerate all-zero columns
    })

    # --- integrative NMF (joint factorization -> consensus clustering) ---
    set.seed(1)
    fit <- nmf.mnnals(dat = dat, k = K)
    group <- if (!is.null(fit\$clusters)) fit\$clusters else apply(fit\$W, 1, which.max)
    samples <- rownames(dat[[1]])

    write.csv(data.frame(sample = samples, cluster = as.integer(group), check.names = FALSE),
              "intnmf_clusters.csv", row.names = FALSE)
    write.csv(data.frame(view = names(data), n_features = vapply(data, ncol, 0L), check.names = FALSE),
              "intnmf_views.csv", row.names = FALSE)

    writeLines(c('"BIOC_INTNMF_MULTIOMICS":',
      paste0('    IntNMF: ', as.character(packageVersion('IntNMF')))), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch intnmf_clusters.csv versions.yml
    """
}

workflow BIOC_INTNMF_MULTIOMICS_WORKFLOW {
    take:
    ch_input   // channel: [ val(meta), [ omics matrices ] ]

    main:
    BIOC_INTNMF_MULTIOMICS(ch_input)

    emit:
    tables   = BIOC_INTNMF_MULTIOMICS.out.tables
    versions = BIOC_INTNMF_MULTIOMICS.out.versions
}
