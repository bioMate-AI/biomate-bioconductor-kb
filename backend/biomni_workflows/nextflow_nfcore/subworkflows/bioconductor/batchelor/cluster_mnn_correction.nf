#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: batchelor — cluster_mnn_correction
// Merge batches conservatively by matching pre-defined cluster labels across different datasets.
// Input: sce1, sce2
// Container: quay.io/biocontainers/bioconductor-batchelor:1.26.0--r45ha27e39d_0
// R packages: SingleCellExperiment, batchelor, scran
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, batchelor, scran
// QC: highly-variable feature selection
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter out unclassified cells
//  * 2. [Core Analysis] Run clusterMNN using pre-defined cluster labels to identify meta-clusters across batches

nextflow.enable.dsl = 2

process BIOC_BATCHELOR_CLUSTER_MNN_CORRECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    tuple val(meta), path("qc_metrics.json"), emit: qc_metrics
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("SingleCellExperiment", "batchelor", "scran")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
            
    # Load required libraries
    library(batchelor)
    library(scran)
    
    # 1. Read user input files from the working directory
    sce1 <- readRDS("sce1.rds")
    sce2 <- readRDS("sce2.rds")
    
    # Filter out unclassified cells
    keep1 <- !is.na(colLabels(sce1)) & tolower(colLabels(sce1)) != "unclassified"
    sce1 <- sce1[, keep1]
    
    keep2 <- !is.na(colLabels(sce2)) & tolower(colLabels(sce2)) != "unclassified"
    sce2 <- sce2[, keep2]
    
    # Preprocessing to obtain chosen.hvgs (required for clusterMNN)
    # Find common genes
    universe <- intersect(rownames(sce1), rownames(sce2))
    sce1 <- sce1[universe, ]
    sce2 <- sce2[universe, ]
    
    # Multi-batch normalization
    norm_outs <- multiBatchNorm(sce1, sce2)
    sce1 <- norm_outs[[1]]
    sce2 <- norm_outs[[2]]
    
    # Identify highly variable genes (HVGs)
    dec1 <- modelGeneVar(sce1)
    dec2 <- modelGeneVar(sce2)
    combined.dec <- combineVar(dec1, dec2)
    chosen.hvgs <- getTopHVGs(combined.dec, n=5000)
    
    # 2. Run clusterMNN
    clust.out <- clusterMNN(sce1, sce2,
        subset.row=chosen.hvgs,
        clusters=list(colLabels(sce1), colLabels(sce2))) 
    
    # 3. Extract meta-clusters
    clust.info <- metadata(clust.out)\$cluster
    meta_clusters <- split(clust.info\$cluster, clust.info\$meta)
    
    # 4. Write outputs
    # Save the corrected SingleCellExperiment object
    saveRDS(clust.out, "clust_out.rds")
    
    # Save the cluster info metadata
    write.csv(as.data.frame(clust.info), "cluster_info.csv", row.names = FALSE)
    
    # Save the meta-clusters mapping
    meta_df <- data.frame(
        meta_cluster_id = rep(names(meta_clusters), lengths(meta_clusters)),
        original_cluster = unlist(meta_clusters),
        stringsAsFactors = FALSE
    )
    write.csv(meta_df, "meta_clusters.csv", row.names = FALSE)
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # HVG selection — count rows with high CV. Pass when 1000-3000 HVGs
    # (Stuart 2019 Cell Seurat v3 default range).
    .hvg_count <- NA_real_; .hvg_files <- character(0)
    for (.hvg_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .hvg_obj <- tryCatch(readRDS(.hvg_rds), error = function(e) NULL)
      .hvg_mat <- if (is.matrix(.hvg_obj) || is.data.frame(.hvg_obj)) .hvg_obj else NULL
      if (!is.null(.hvg_mat) && nrow(.hvg_mat) > 200) {
        .hvg_m <- suppressWarnings(as.matrix(.hvg_mat))
        .hvg_cvs <- suppressWarnings(apply(.hvg_m, 1, function(r) {
          .rv <- as.numeric(r); .m <- mean(.rv, na.rm = TRUE)
          if (is.finite(.m) && .m > 0) sd(.rv, na.rm = TRUE) / .m else NA_real_
        }))
        .hvg_count <- sum(is.finite(.hvg_cvs) & .hvg_cvs > 1.0)
        .hvg_files <- c(.hvg_files, .hvg_rds); break
      }
    }
    .gates_by_label[["highly-variable feature selection"]] <- list(
      gate_row = "bioc_hvg_selection",
      metric_name = "hvg_count",
      metric_value = .hvg_count,
      passes = isTRUE(is.finite(.hvg_count) && .hvg_count >= 1000 && .hvg_count <= 3000),
      status = if (is.finite(.hvg_count)) paste0("computed (CV>1.0 rows = ", .hvg_count, "; proxy for HVG selection)")
               else "not_computed (no expression matrix .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_BATCHELOR_CLUSTER_MNN_CORRECTION",
      domain  = "bioconductor",
      declared_qc_steps = c("highly-variable feature selection"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_BATCHELOR_CLUSTER_MNN_CORRECTION":',
        paste0('    batchelor: ', as.character(packageVersion('batchelor')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cluster_mnn_correction.csv versions.yml
    """
}

workflow BIOC_BATCHELOR_CLUSTER_MNN_CORRECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce1, sce2 ] ]

    main:
    BIOC_BATCHELOR_CLUSTER_MNN_CORRECTION(ch_input)

    emit:
    tables   = BIOC_BATCHELOR_CLUSTER_MNN_CORRECTION.out.tables
    plots    = BIOC_BATCHELOR_CLUSTER_MNN_CORRECTION.out.plots
    objects  = BIOC_BATCHELOR_CLUSTER_MNN_CORRECTION.out.objects
    versions = BIOC_BATCHELOR_CLUSTER_MNN_CORRECTION.out.versions
}
