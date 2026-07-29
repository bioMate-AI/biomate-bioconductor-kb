#!/usr/bin/env nextflow
// ============================================================
// DRAFT / UNTESTED — Bioconductor workflow: StabMap — single-cell mosaic integration
// StabMap (Ghazanfar et al. 2024, Nat Biotech) — top MOSAIC single-cell integration method
// and the most efficient in scMultiBench 2025. Projects each modality onto a common
// low-dimensional embedding via a mosaic data topology, tolerating unshared features/cells.
// FIRST single-cell method in BioMate (Path A: unify bulk + single-cell SOTA). Reuses the
// existing R bioc container (StabMap is R/Bioconductor). Same universal CSV interface as the
// bulk methods (features × cells; "samples" = cells); standardized clusters.csv output.
//
// ⚠️ DRAFT — NOT YET RUN ON BATCH. Two things to de-risk on first run:
//   (1) StabMap has ~44 Bioc deps; the runtime source install may be slow → if so, bake a
//       dedicated :3.20-stabmap image (MOFA2 pattern) instead of installing at runtime.
//   (2) This exercises StabMap's VERTICAL/shared-cell mode via the CSV interface; true
//       MOSAIC (unshared features/cells) needs .h5ad input + explicit topology (Phase 2).
// Input: omics
// Container: bioc-domain-general:3.20-slim (StabMap from Bioconductor at runtime)
// R packages: StabMap (+ SingleCellExperiment, scran deps)
// ============================================================

nextflow.enable.dsl = 2

process BIOC_STABMAP_SINGLECELL {
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
    # StabMap is Bioconductor — install via EXPLICIT Bioc source repos + p3m CRAN binary to
    # avoid the container-binaries mirror 504 (the MOFA2 lesson). Deps resolve from the same.
    if (!requireNamespace("StabMap", quietly = TRUE))
      install.packages("StabMap",
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

    suppressMessages({ library(StabMap) })

    # --- read the per-modality matrices (UNIVERSAL interface; features x cells) ---
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

    # [biomate] align all modalities to their COMMON cells (columns), consistent order.
    # (Vertical/shared-cell mode. True mosaic with unshared cells is Phase-2 via .h5ad.)
    .common <- Reduce(intersect, lapply(data, colnames))
    stopifnot(length(.common) >= 2)
    data <- lapply(data, function(m) { M <- m[, .common, drop = FALSE]
      for (i in seq_len(nrow(M))) { v <- M[i, ]; if (any(is.na(v))) { mu <- mean(v, na.rm = TRUE); v[is.na(v)] <- if (is.finite(mu)) mu else 0; M[i, ] <- v } }
      M })
    cat(sprintf("[stabmap] %d modalities aligned to %d common cells\\n", length(data), length(.common)))

    # --- StabMap mosaic integration -> joint cell embedding -> cluster ---
    K <- ${params.n_clusters ?: 4}L   # clusters; pass n_clusters to match the label's class count
    assay_list <- data                 # named list of matrices, features x cells
    stab <- stabMap(assay_list, reference_list = names(assay_list), plot = FALSE)
    # stab: cells x dims embedding
    set.seed(1)
    group <- kmeans(as.matrix(stab), centers = K, nstart = 10)\$cluster
    cells <- rownames(stab); if (is.null(cells)) cells <- .common

    write.csv(data.frame(sample = cells, cluster = as.integer(group), check.names = FALSE),
              "stabmap_clusters.csv", row.names = FALSE)
    write.csv(data.frame(modality = names(data), n_features = vapply(data, nrow, 0L), check.names = FALSE),
              "stabmap_modalities.csv", row.names = FALSE)

    writeLines(c('"BIOC_STABMAP_SINGLECELL":',
      paste0('    StabMap: ', as.character(packageVersion('StabMap')))), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch stabmap_clusters.csv versions.yml
    """
}

workflow BIOC_STABMAP_SINGLECELL_WORKFLOW {
    take:
    ch_input   // channel: [ val(meta), [ modality matrices ] ]

    main:
    BIOC_STABMAP_SINGLECELL(ch_input)

    emit:
    tables   = BIOC_STABMAP_SINGLECELL.out.tables
    versions = BIOC_STABMAP_SINGLECELL.out.versions
}
