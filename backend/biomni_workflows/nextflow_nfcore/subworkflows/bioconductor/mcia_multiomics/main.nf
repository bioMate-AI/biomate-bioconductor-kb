#!/usr/bin/env nextflow
// ============================================================
// Bioconductor-style workflow: MCIA — multiple co-inertia analysis multi-omics clustering
// Multiple Co-Inertia Analysis (Meng et al. 2014, omicade4) — the method Cantini et al.
// 2021 found MOST ROBUST across contexts among 9 joint-DR approaches. Finds a common
// co-structure across all omics layers (maximizing squared covariance of each table with
// a reference synthetic structure), then clusters samples on the shared synthetic axes.
// Part of the BioMate multi-omics SOTA method set — same universal CSV input contract as
// MOFA2/SNF/intNMF, standardized clusters.csv output.
// Input: omics
// Container: bioc-domain-general:3.20-slim (omicade4 from Bioconductor at runtime)
// R packages: omicade4 (ade4, made4)
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MCIA_MULTIOMICS {
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
    # omicade4 is Bioconductor. Install with EXPLICIT standard Bioc source repos + CRAN —
    # NOT the BiocManager container-binaries mirror, which 504s. Deps ade4 (CRAN) + made4
    # (Bioc) resolve from this repo set.
    if (!requireNamespace("omicade4", quietly = TRUE))
      install.packages("omicade4",
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

    suppressMessages({ library(omicade4) })

    # --- read the multi-omics view list (UNIVERSAL interface, same as MOFA2/SNF/intNMF) ---
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
    # differ per omic). MCIA requires identical samples/order (columns) across tables.
    .common <- Reduce(intersect, lapply(data, colnames))
    stopifnot(length(.common) >= 2)
    data <- lapply(data, function(m) m[, .common, drop = FALSE])
    cat(sprintf("[mcia] %d views aligned to %d common samples\\n", length(data), length(.common)))

    # --- MCIA data prep: features x samples (NO transpose), NON-NEGATIVE (mcia default
    # nsc=TRUE runs non-symmetric COA, which requires non-negative data), NA-imputed ---
    dat <- lapply(data, function(m) {
      M <- as.matrix(m); storage.mode(M) <- "double"
      for (i in seq_len(nrow(M))) {              # impute NAs by feature (row) mean
        v <- M[i, ]; if (any(is.na(v))) { mu <- mean(v, na.rm = TRUE); v[is.na(v)] <- if (is.finite(mu)) mu else 0; M[i, ] <- v }
      }
      if (min(M) < 0) M <- M - min(M)            # shift to non-negative for COA
      M <- M[apply(M, 1, function(r) stats::sd(r) > 0), , drop = FALSE]  # drop constant/all-zero features
      M <- M + 1e-6                              # strict positivity: every feature "expressed" in ALL samples
                                                 # (mcia nsc COA rejects features with a zero in any observation)
      as.data.frame(M)
    })

    # --- multiple co-inertia analysis -> synthetic sample axes -> cluster ---
    K <- ${params.n_clusters ?: 3}L   # number of clusters; pass n_clusters to match the
                                       # label's class count for fair cross-method comparison
    .nf <- min(10L, length(.common) - 1L); if (.nf < 2L) .nf <- 2L   # MCIA factors (>=2)
    res <- mcia(dat, cia.nf = .nf)
    scores <- as.matrix(res\$mcoa\$SynVar)          # samples x synthetic axes
    set.seed(1)
    group <- kmeans(scores, centers = K, nstart = 10)\$cluster
    samples <- rownames(scores); if (is.null(samples)) samples <- colnames(data[[1]])

    write.csv(data.frame(sample = samples, cluster = as.integer(group), check.names = FALSE),
              "mcia_clusters.csv", row.names = FALSE)
    write.csv(data.frame(view = names(data), n_features = vapply(data, nrow, 0L), check.names = FALSE),
              "mcia_views.csv", row.names = FALSE)

    writeLines(c('"BIOC_MCIA_MULTIOMICS":',
      paste0('    omicade4: ', as.character(packageVersion('omicade4')))), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch mcia_clusters.csv versions.yml
    """
}

workflow BIOC_MCIA_MULTIOMICS_WORKFLOW {
    take:
    ch_input   // channel: [ val(meta), [ omics matrices ] ]

    main:
    BIOC_MCIA_MULTIOMICS(ch_input)

    emit:
    tables   = BIOC_MCIA_MULTIOMICS.out.tables
    versions = BIOC_MCIA_MULTIOMICS.out.versions
}
