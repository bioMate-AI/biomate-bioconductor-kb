#!/usr/bin/env nextflow
// ============================================================
// Bioconductor-style workflow: SNF — similarity_network_fusion_multiomics
// Similarity Network Fusion (Wang et al. 2014, Nat Methods) integration of ANY
// combination of omics layers into a single fused patient-similarity network, then
// spectral clustering into subtypes. Method #2 in the BioMate multi-omics benchmark
// harness (alongside MOFA2) — same universal CSV input contract, standardized
// clusters.csv output for the metric harness.
// Input: omics
// Container: bioc-domain-general:3.20-slim (SNFtool + cluster from CRAN at runtime)
// R packages: SNFtool, cluster
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SNF_MULTIOMICS {
    tag "${meta.id}"
    label 'process_medium'

    publishDir "${params.outdir}", mode: 'copy'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables,  optional: true
    tuple val(meta), path("*.pdf"), emit: plots,   optional: true
    path "qc_metrics.json",         emit: qc,       optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # SNFtool + cluster are CRAN — install as fast p3m.dev noble binaries (no Bioc
    # container-binaries mirror, so no 504). cluster is usually already present.
    .need <- c("SNFtool", "cluster", "jsonlite")
    .miss <- .need[!vapply(.need, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.miss)) install.packages(.miss, Ncpus = 2)

    # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
    for (.bm_d in list.files(".", full.names = TRUE)) {
      if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
        for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
          if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
        }
      }
    }

    suppressMessages({ library(SNFtool) })

    # --- Assemble the multi-omics view list (UNIVERSAL interface, same as MOFA2) ---
    # One named .csv/.tsv per omics modality; view name = filename. Matrices are
    # features x samples (col 1 = feature IDs, header = sample IDs).
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

    # [biomate] align all views to their COMMON samples, in a consistent order. Real
    # cohorts (e.g. TCGA) measure each omic on a different, overlapping sample set;
    # SNF requires identical samples/order across views (else non-conformable arrays).
    .common <- Reduce(intersect, lapply(data, colnames))
    stopifnot(length(.common) >= 2)
    data <- lapply(data, function(m) m[, .common, drop = FALSE])
    cat(sprintf("[snf] %d views aligned to %d common samples\\n", length(data), length(.common)))

    # --- SNF pipeline ---
    K <- 20L      # KNN neighbours (SNF default)
    alpha <- 0.5  # kernel width (SNF default)
    Tt <- 20L     # SNF fusion iterations (SNF default)
    C <- ${params.n_clusters ?: 3}L   # subtypes to extract; pass n_clusters to match the
                                       # label's class count for fair cross-method comparison

    Wall <- lapply(data, function(m) {
      X <- t(as.matrix(m))                    # SNF expects samples x features
      # impute NAs by feature mean (many real cohorts measure a modality on a subset)
      for (j in seq_len(ncol(X))) {
        v <- X[, j]; if (any(is.na(v))) { mu <- mean(v, na.rm = TRUE); v[is.na(v)] <- if (is.finite(mu)) mu else 0; X[, j] <- v }
      }
      X <- standardNormalization(X)           # z-normalize features
      D <- dist2(as.matrix(X), as.matrix(X))  # squared euclidean
      affinityMatrix(D, K, alpha)
    })

    W <- SNF(Wall, K, Tt)
    group <- spectralClustering(W, C)
    samples <- rownames(W); if (is.null(samples)) samples <- colnames(data[[1]])

    # Standardized output for the metric harness: sample, cluster
    write.csv(data.frame(sample = samples, cluster = group, check.names = FALSE),
              "snf_clusters.csv", row.names = FALSE)

    # [biomate] QC via DECLARED gates (data-driven). Multi-omics integration has no
    # hardcoded branch in the QC monitor; the gates travel as data in qc_metrics.json
    # and are evaluated generically by galaxy.ai.qc_gate_engine (the BIOC_ substring
    # already routes this process's qc_metrics.json to the monitor). Metrics describe
    # the clustering the fusion produced; gates assert it is non-degenerate & separated.
    .n_clusters <- length(unique(group))
    .min_frac   <- min(table(group)) / length(group)
    .mean_sil   <- 0
    try({
      if (.n_clusters >= 2) {
        .Wn  <- W / max(W, na.rm = TRUE)          # affinity -> [0,1] similarity
        .sil <- cluster::silhouette(as.integer(group), as.dist(1 - .Wn))
        if (!is.null(.sil)) .mean_sil <- as.numeric(mean(.sil[, "sil_width"]))
      }
    }, silent = TRUE)
    if (!is.finite(.mean_sil)) .mean_sil <- 0
    .qc <- list(
      mean_silhouette      = round(.mean_sil, 4),
      n_clusters_found     = .n_clusters,
      min_cluster_fraction = round(.min_frac, 4),
      n_samples            = length(group),
      gates = list(
        list(metric = "n_clusters_found", op = ">=", threshold = 2, severity = "halt",
             name = "Non-degenerate integration",
             evidence = "SNF must resolve >=2 subtypes; one cluster means the fusion found no structure",
             provenance = "heuristic"),
        list(metric = "mean_silhouette", op = ">=", threshold = 0.10, severity = "advisory",
             name = "Subtype separation (silhouette)",
             evidence = "Rousseeuw 1987 J Comput Appl Math; mean silhouette >=0.1 indicates non-trivial structure",
             provenance = "literature"),
        list(metric = "min_cluster_fraction", op = ">=", threshold = 0.05, severity = "advisory",
             name = "Subtype balance",
             evidence = "a subtype with <5% of samples is likely an outlier cluster, not a robust stratum",
             provenance = "heuristic")
      )
    )
    jsonlite::write_json(.qc, "qc_metrics.json", auto_unbox = TRUE, pretty = TRUE)
    # Fused affinity + per-view weights for downstream inspection
    write.csv(data.frame(view = names(data), n_features = vapply(data, nrow, 0L), check.names = FALSE),
              "snf_views.csv", row.names = FALSE)
    saveRDS(W, "snf_fused_affinity.rds")

    pdf("snf_analysis_plots.pdf", width = 9, height = 8)
    try(displayClustersWithHeatmap(W, group), silent = TRUE)
    dev.off()

    writeLines(c('"BIOC_SNF_MULTIOMICS":',
      paste0('    SNFtool: ', as.character(packageVersion('SNFtool')))), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_snf_clusters.csv versions.yml
    """
}

workflow BIOC_SNF_MULTIOMICS_WORKFLOW {
    take:
    ch_input   // channel: [ val(meta), [ omics matrices ] ]

    main:
    BIOC_SNF_MULTIOMICS(ch_input)

    emit:
    tables   = BIOC_SNF_MULTIOMICS.out.tables
    plots    = BIOC_SNF_MULTIOMICS.out.plots
    versions = BIOC_SNF_MULTIOMICS.out.versions
}
