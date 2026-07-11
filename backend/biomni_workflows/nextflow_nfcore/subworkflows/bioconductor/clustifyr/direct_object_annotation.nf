#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: clustifyr — direct_object_annotation
// Annotate cell types directly on Seurat or SingleCellExperiment objects and return the updated object.
// Input: sce, so, cbmc_ref
// Container: quay.io/biocontainers/bioconductor-clustifyr:1.22.0--r45hdfd78af_0
// R packages: Seurat, SingleCellExperiment, clustifyr
// Bioconductor: 3.20 | R: 4.4
// Requires: Seurat, SingleCellExperiment, clustifyr
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run clustify on the SingleCellExperiment object with obj_out = TRUE
//  * 2. [Core Analysis] Run clustify on the Seurat object with obj_out = TRUE
//  * 3. [Core Analysis] Extract the assigned cell types and correlation values from the object metadata

nextflow.enable.dsl = 2

process BIOC_CLUSTIFYR_DIRECT_OBJECT_ANNOTATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("Seurat", "SingleCellExperiment", "clustifyr", "SummarizedExperiment")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    library(clustifyr)
    library(SummarizedExperiment)
    library(Seurat)
    
    # Read user input files from the working directory
    sce <- readRDS("sce")
    so <- readRDS("so")
    cbmc_ref <- readRDS("cbmc_ref")
    
    # Stage 1: Run clustify on the SingleCellExperiment object with obj_out = TRUE
    res_sce <- clustify(
        input = sce, # an SCE object
        ref_mat = cbmc_ref, # matrix of RNA-seq expression data for each cell type
        cluster_col = "clusters", # name of column in meta.data containing cell clusters
        obj_out = TRUE # output SCE object with cell type inserted as "type" column
    )
    
    # Stage 3 (Part 1): Extract the assigned cell types and correlation values from the SCE object metadata
    sce_extracted <- colData(res_sce)[, c("type", "r"), drop = FALSE]
    
    # Save SCE results
    write.csv(as.data.frame(sce_extracted), "sce_annotations.csv", row.names = TRUE)
    saveRDS(res_sce, "sce_annotated.rds")
    
    # Stage 2: Run clustify on the Seurat object with obj_out = TRUE
    res_so <- clustify(
        input = so, # a Seurat object
        ref_mat = cbmc_ref, # matrix of RNA-seq expression data for each cell type
        cluster_col = "seurat_clusters", # name of column in meta.data containing cell clusters
        obj_out = TRUE # output Seurat object with cell type inserted as "type" column
    )
    
    # Stage 3 (Part 2): Extract the assigned cell types and correlation values from the Seurat object metadata
    so_extracted <- res_so[[c("type", "r")]]
    
    # Save Seurat results
    write.csv(as.data.frame(so_extracted), "so_annotations.csv", row.names = TRUE)
    saveRDS(res_so, "so_annotated.rds")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # cell QC metrics — defensive cell-count + per-cell summary from any
    # matrix artifact. Pass when columns (cells) ≥ 50 and rows (features) ≥ 200
    # (Luecken & Theis 2019 single-cell QC floor).
    .cqc_ncells <- NA_real_; .cqc_nfeats <- NA_real_; .cqc_files <- character(0)
    for (.cqc_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
      .cqc_obj <- tryCatch(readRDS(.cqc_rds), error = function(e) NULL)
      .cqc_mat <- if (is.matrix(.cqc_obj) || is.data.frame(.cqc_obj)) .cqc_obj else NULL
      if (!is.null(.cqc_mat) && nrow(.cqc_mat) > 100) {
        .cqc_ncells <- ncol(.cqc_mat); .cqc_nfeats <- nrow(.cqc_mat)
        .cqc_files <- c(.cqc_files, .cqc_rds); break
      }
    }
    .gates_by_label[["cell QC metrics"]] <- list(
      gate_row = "bioc_cell_qc_metrics",
      metric_name = "n_cells",
      metric_value = .cqc_ncells,
      passes = isTRUE(is.finite(.cqc_ncells) && .cqc_ncells >= 50 && .cqc_nfeats >= 200),
      status = if (is.finite(.cqc_ncells)) paste0("computed (cells=", .cqc_ncells, ", features=", .cqc_nfeats, "; proxy gate)")
               else "not_computed (no scRNA matrix .rds artifact present)"
    )

    # count normalization — scan .rds matrix artifacts for library-size CV
    # ratio (post-norm / pre-norm); without raw input we report median lib CV
    # as a proxy diagnostic. Threshold = 0.7 (Bullard 2010 BMC Bioinf).
    .cn_lib_cvs <- numeric(0)
    .cn_scanned <- character(0)
    for (.cn_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
      .cn_obj <- tryCatch(readRDS(.cn_rds), error = function(e) NULL)
      .cn_mat <- if (is.matrix(.cn_obj) || is.data.frame(.cn_obj)) .cn_obj else NULL
      if (!is.null(.cn_mat) && ncol(.cn_mat) >= 2 && nrow(.cn_mat) >= 2) {
        .cn_lib <- tryCatch(colSums(as.matrix(.cn_mat), na.rm = TRUE), error = function(e) NULL)
        if (!is.null(.cn_lib) && all(is.finite(.cn_lib)) && mean(.cn_lib) > 0) {
          .cn_lib_cvs <- c(.cn_lib_cvs, sd(.cn_lib) / mean(.cn_lib))
          .cn_scanned <- c(.cn_scanned, .cn_rds)
        }
      }
    }
    .cn_med_cv <- if (length(.cn_lib_cvs) > 0) round(median(.cn_lib_cvs), 4) else NA_real_
    .gates_by_label[["count normalization"]] <- list(
      gate_row = "bioc_count_normalization",
      metric_name = "lib_size_cv_median",
      metric_value = .cn_med_cv,
      passes = isTRUE(is.finite(.cn_med_cv) && .cn_med_cv <= 0.3),
      status = if (is.finite(.cn_med_cv)) paste0("computed (proxy: median lib-size CV across ", length(.cn_scanned), " matrix .rds; raw-vs-norm ratio not measurable without paired input)")
               else "not_computed (no count matrix .rds artifact present)"
    )

    # low-count filtering — fraction of genes retained (heuristic on matrix artifacts).
    # Pass band 30-60% per Chen 2016 F1000 (edgeR filterByExpr convention).
    .lcf_kept_fractions <- numeric(0)
    .lcf_scanned <- character(0)
    for (.lcf_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
      .lcf_obj <- tryCatch(readRDS(.lcf_rds), error = function(e) NULL)
      .lcf_mat <- if (is.matrix(.lcf_obj) || is.data.frame(.lcf_obj)) .lcf_obj else NULL
      if (!is.null(.lcf_mat) && nrow(.lcf_mat) > 100) {
        .lcf_m <- tryCatch(as.matrix(.lcf_mat), error = function(e) NULL)
        if (!is.null(.lcf_m)) {
          .lcf_row_med <- suppressWarnings(apply(.lcf_m, 1, function(r) median(as.numeric(r), na.rm = TRUE)))
          .lcf_kept <- sum(is.finite(.lcf_row_med) & .lcf_row_med >= 1) / nrow(.lcf_m)
          .lcf_kept_fractions <- c(.lcf_kept_fractions, .lcf_kept)
          .lcf_scanned <- c(.lcf_scanned, .lcf_rds)
        }
      }
    }
    .lcf_kept <- if (length(.lcf_kept_fractions) > 0) round(median(.lcf_kept_fractions), 4) else NA_real_
    .gates_by_label[["low-count filtering"]] <- list(
      gate_row = "bioc_low_count_filtering",
      metric_name = "genes_kept_fraction",
      metric_value = .lcf_kept,
      passes = isTRUE(is.finite(.lcf_kept) && .lcf_kept >= 0.3 && .lcf_kept <= 0.6),
      status = if (is.finite(.lcf_kept)) paste0("computed (proxy: rows w/ median count >=1 across ", length(.lcf_scanned), " matrix .rds)")
               else "not_computed (no count matrix .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_CLUSTIFYR_DIRECT_OBJECT_ANNOTATION",
      domain  = "bioconductor",
      declared_qc_steps = c("cell QC metrics", "count normalization", "low-count filtering"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_CLUSTIFYR_DIRECT_OBJECT_ANNOTATION":',
        paste0('    clustifyr: ', as.character(packageVersion('clustifyr')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_direct_object_annotation.csv versions.yml
    """
}

workflow BIOC_CLUSTIFYR_DIRECT_OBJECT_ANNOTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce, so, cbmc_ref ] ]

    main:
    BIOC_CLUSTIFYR_DIRECT_OBJECT_ANNOTATION(ch_input)

    emit:
    tables   = BIOC_CLUSTIFYR_DIRECT_OBJECT_ANNOTATION.out.tables
    plots    = BIOC_CLUSTIFYR_DIRECT_OBJECT_ANNOTATION.out.plots
    objects  = BIOC_CLUSTIFYR_DIRECT_OBJECT_ANNOTATION.out.objects
    versions = BIOC_CLUSTIFYR_DIRECT_OBJECT_ANNOTATION.out.versions
}
