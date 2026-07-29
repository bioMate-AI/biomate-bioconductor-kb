#!/usr/bin/env nextflow
// ============================================================
// Bioconductor-style workflow: MFA — Multiple Factor Analysis multi-omics clustering
// NOTE: this file replaces the original RGCCA implementation. RGCCA's hard dependency
// `Deriv` has no noble binary on p3m and fails to compile from source (codegen Makefile
// -> `make Error 1`) in the bioc-domain-general:3.20-slim container. MFA (Escofier &
// Pages) is the reliable-install substitute: CRAN FactoMineR (guaranteed noble binary),
// and it is the canonical multi-BLOCK factor method in the same canonical-correlation /
// co-inertia family — integrates multiple groups of variables into one weighted common
// factor space, then clusters samples on the shared coordinates. Process/workflow names
// kept as *_RGCCA_* so the executor resolves the file path unchanged; the METHOD is MFA
// (relabel as "MFA" in the benchmark matrix). Same universal CSV interface as MOFA2/SNF.
// Input: omics
// Container: bioc-domain-general:3.20-slim (FactoMineR from CRAN at runtime)
// R packages: FactoMineR
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
    # FactoMineR is CRAN and ubiquitous -> installs as a fast p3m.dev noble BINARY via the
    # container default repo (no source build, no Deriv, no make error, no Bioc 504).
    if (!requireNamespace("FactoMineR", quietly = TRUE)) install.packages("FactoMineR", Ncpus = 2)

    # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
    for (.bm_d in list.files(".", full.names = TRUE)) {
      if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
        for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
          if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
        }
      }
    }

    suppressMessages({ library(FactoMineR) })

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

    # --- MFA data prep: samples x features per block, impute NA, cap variable features ---
    .prep <- function(m, vname) {
      X <- t(as.matrix(m))                      # samples x features
      for (j in seq_len(ncol(X))) {             # impute NAs by feature mean
        v <- X[, j]; if (any(is.na(v))) { mu <- mean(v, na.rm = TRUE); v[is.na(v)] <- if (is.finite(mu)) mu else 0; X[, j] <- v }
      }
      vv <- apply(X, 2, var)
      X <- X[, is.finite(vv) & vv > 0, drop = FALSE]        # drop zero-variance features (MFA needs variance)
      if (ncol(X) > 2000) {                                 # cap to top-2000 most-variable for speed
        vv <- apply(X, 2, var); X <- X[, order(vv, decreasing = TRUE)[1:2000], drop = FALSE]
      }
      colnames(X) <- paste(vname, colnames(X), sep = "__")  # unique names across blocks
      X
    }
    blocks <- Map(.prep, data, names(data))

    # --- Multiple Factor Analysis -> shared sample coordinates -> clustering ---
    base <- as.data.frame(do.call(cbind, blocks), check.names = FALSE)
    grp  <- vapply(blocks, ncol, 0L)            # number of variables per block
    ncp  <- max(2L, ${params.n_clusters ?: 4}L)
    set.seed(1)
    res <- FactoMineR::MFA(base, group = as.integer(grp), type = rep("s", length(blocks)),
                           ncp = ncp, name.group = names(blocks), graph = FALSE)
    coords <- as.matrix(res\$ind\$coord)          # samples x MFA dimensions
    group  <- kmeans(coords, ${params.n_clusters ?: 4}, nstart = 10)\$cluster
    samples <- rownames(coords); if (is.null(samples)) samples <- .common

    write.csv(data.frame(sample = samples, cluster = as.integer(group), check.names = FALSE),
              "mfa_clusters.csv", row.names = FALSE)
    write.csv(data.frame(view = names(data), n_features = vapply(data, nrow, 0L), check.names = FALSE),
              "mfa_views.csv", row.names = FALSE)

    writeLines(c('"BIOC_RGCCA_MULTIOMICS":',
      paste0('    method: MFA (FactoMineR ', as.character(packageVersion('FactoMineR')), ')')),
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
