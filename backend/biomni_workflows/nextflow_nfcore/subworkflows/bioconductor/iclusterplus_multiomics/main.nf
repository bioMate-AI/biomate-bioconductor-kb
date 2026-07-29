#!/usr/bin/env nextflow
// ============================================================
// Bioconductor-style workflow: iClusterPlus — Bayesian latent multi-omics subtyping
// iClusterBayes (Mo, Shen et al.) — canonical Bayesian integrative clustering: a shared
// low-dimensional latent-variable model across all omics layers, then subtype assignment
// from the joint posterior. Part of the BioMate multi-omics SOTA method set — same
// universal CSV input contract as MOFA2/SNF/intNMF, standardized clusters.csv output.
// Input: omics
// Container: bioc-domain-general:3.20-slim (iClusterPlus from Bioconductor at runtime)
// R packages: iClusterPlus
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ICLUSTERPLUS_MULTIOMICS {
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
    # iClusterPlus is Bioconductor — install from explicit standard Bioc source repos to
    # AVOID the BioCcontainers binary mirror that returns 504 (documented saga). p3m.dev
    # provides fast noble binaries for the CRAN dependencies.
    if (!requireNamespace("iClusterPlus", quietly = TRUE))
      install.packages("iClusterPlus",
        repos = c("https://bioconductor.org/packages/3.20/bioc",
                  "https://bioconductor.org/packages/3.20/data/annotation",
                  "https://p3m.dev/cran/__linux__/noble/latest"),
        type = "source", Ncpus = 2)

    # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
    for (.bm_d in list.files(".", full.names = TRUE)) {
      if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
        for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
          if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
        }
      }
    }

    suppressMessages({ library(iClusterPlus) })

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
    # differ per omic). iClusterBayes requires identical samples/order across datasets.
    .common <- Reduce(intersect, lapply(data, colnames))
    stopifnot(length(.common) >= 2)
    data <- lapply(data, function(m) m[, .common, drop = FALSE])
    cat(sprintf("[iclusterplus] %d views aligned to %d common samples\\n", length(data), length(.common)))

    # --- iClusterBayes data prep: SAMPLES x FEATURES, complete, standardized, feature-capped ---
    # Cap each view to its top ~2000 most-variable features to bound runtime (Bayesian
    # MCMC is O(features)); impute NAs by column mean; z-score for the gaussian model.
    dts <- lapply(data, function(m) {
      M <- as.matrix(m)                                  # features x samples
      if (nrow(M) > 2000L) {
        .v <- apply(M, 1, function(.r) var(.r, na.rm = TRUE))
        M <- M[order(.v, decreasing = TRUE)[seq_len(2000L)], , drop = FALSE]
      }
      X <- t(M)                                          # samples x features
      for (j in seq_len(ncol(X))) {
        v <- X[, j]; if (any(is.na(v))) { mu <- mean(v, na.rm = TRUE); v[is.na(v)] <- if (is.finite(mu)) mu else 0; X[, j] <- v }
      }
      X <- scale(X); X[!is.finite(X)] <- 0               # gaussian model expects standardized input
      X
    })

    # --- iClusterBayes (Bayesian latent integrative clustering) ---
    # K = number of latent variables = (n_clusters - 1); n.burnin/n.draw kept modest for
    # tractable runtime. iClusterBayes takes FIXED dt1..dt6 args (not a list) -> do.call.
    Klat <- ${params.n_clusters ?: 4}L - 1L
    .dt_args <- list()
    for (.i in seq_along(dts)) .dt_args[[paste0("dt", .i)]] <- dts[[.i]]
    .call_args <- c(.dt_args,
                    list(type = rep("gaussian", length(dts)),
                         K = max(Klat, 1L), n.burnin = 200L, n.draw = 400L))
    set.seed(1)
    fit <- do.call(iClusterPlus::iClusterBayes, .call_args)
    group <- fit\$clusters
    samples <- rownames(dts[[1]])

    write.csv(data.frame(sample = samples, cluster = as.integer(group), check.names = FALSE),
              "iclusterplus_clusters.csv", row.names = FALSE)
    write.csv(data.frame(view = names(data), n_features = vapply(dts, ncol, 0L), check.names = FALSE),
              "iclusterplus_views.csv", row.names = FALSE)

    writeLines(c('"BIOC_ICLUSTERPLUS_MULTIOMICS":',
      paste0('    iClusterPlus: ', as.character(packageVersion('iClusterPlus')))), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch iclusterplus_clusters.csv versions.yml
    """
}

workflow BIOC_ICLUSTERPLUS_MULTIOMICS_WORKFLOW {
    take:
    ch_input   // channel: [ val(meta), [ omics matrices ] ]

    main:
    BIOC_ICLUSTERPLUS_MULTIOMICS(ch_input)

    emit:
    tables   = BIOC_ICLUSTERPLUS_MULTIOMICS.out.tables
    versions = BIOC_ICLUSTERPLUS_MULTIOMICS.out.versions
}
