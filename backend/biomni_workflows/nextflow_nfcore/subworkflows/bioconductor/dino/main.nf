#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Dino — standard_matrix_normalization_and_seurat
// Filter and normalize a raw UMI count matrix using Dino, then convert it to a Seurat object for downstream clustering and visualization.
// Input: pbmcSmall
// Container: quay.io/biocontainers/bioconductor-dino:1.16.0--r45hdfd78af_0
// R packages: Dino, knitr, Matrix, scran, Seurat, SingleCellExperiment
// Bioconductor: 3.20 | R: 4.4
// Requires: Dino, Matrix, Seurat
// Visualizations: UMAP/t-SNE plot, UMAP plot
// QC: low-count filtering, highly-variable feature selection, clustering QC
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter out genes with low non-zero expression
//  * 2. [Core Analysis] Normalize the UMI count matrix using Dino
//  * 3. [Core Analysis] Convert the normalized matrix into a Seurat object using SeuratFromDino
//  * 4. [Visualization & Output] Run downstream Seurat clustering and visualization (FindVariableFeatures, ScaleData, RunPCA, FindNeighbors, FindClusters, RunUMAP,

nextflow.enable.dsl = 2

process BIOC_DINO_STANDARD_MATRIX_NORMALIZATION_AND_SEURAT {
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
    .bm_deps <- c("Dino", "knitr", "Matrix", "scran", "Seurat", "SingleCellExperiment")
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
    library(Dino)
    library(Seurat)
    library(Matrix)
    
    # -----------------------------------------------------------------------------
    # Stage 1: Read User Input File
    # -----------------------------------------------------------------------------
    # The pipeline expects 'pbmcSmall' in the working directory.
    # We support RDS, CSV, TSV, or a generic text file.
    if (file.exists("pbmcSmall.rds")) {
      pbmcSmall <- readRDS("pbmcSmall.rds")
    } else if (file.exists("pbmcSmall.csv")) {
      pbmcSmall <- read.csv("pbmcSmall.csv", row.names = 1, check.names = FALSE)
      pbmcSmall <- as.matrix(pbmcSmall)
    } else if (file.exists("pbmcSmall.tsv")) {
      pbmcSmall <- read.delim("pbmcSmall.tsv", row.names = 1, check.names = FALSE)
      pbmcSmall <- as.matrix(pbmcSmall)
    } else if (file.exists("pbmcSmall")) {
      pbmcSmall <- tryCatch({
        readRDS("pbmcSmall")
      }, error = function(e) {
        as.matrix(read.table("pbmcSmall", header = TRUE, row.names = 1, check.names = FALSE))
      })
    } else {
      stop("Required input file 'pbmcSmall' (RDS, CSV, or TSV format) not found in the working directory.")
    }
    
    # Ensure the input is a matrix or sparse matrix
    if (!inherits(pbmcSmall, c("matrix", "dgCMatrix"))) {
      pbmcSmall <- as.matrix(pbmcSmall)
    }
    
    # -----------------------------------------------------------------------------
    # Stage 2: Clean UMI Data (Filter out genes with low non-zero expression)
    # -----------------------------------------------------------------------------
    pbmcSmall <- pbmcSmall[rowSums(pbmcSmall != 0) >= 20, ]
    
    # -----------------------------------------------------------------------------
    # Stage 3: Normalize UMI Count Matrix using Dino
    # -----------------------------------------------------------------------------
    pbmcSmall_Norm <- Dino(pbmcSmall)
    
    # Save the normalized matrix
    saveRDS(pbmcSmall_Norm, file = "pbmcSmall_Norm.rds")
    
    # -----------------------------------------------------------------------------
    # Stage 4: Convert to Seurat and Run Downstream Clustering & Visualization
    # -----------------------------------------------------------------------------
    pbmcSmall_Seurat <- SeuratFromDino(pbmcSmall_Norm, doNorm = FALSE)
    
    pbmcSmall_Seurat <- FindVariableFeatures(pbmcSmall_Seurat, 
                            selection.method = "mvp")
    
    pbmcSmall_Seurat <- ScaleData(pbmcSmall_Seurat, 
                            features = rownames(pbmcSmall_Norm))
    
    pbmcSmall_Seurat <- RunPCA(pbmcSmall_Seurat, 
                            features = VariableFeatures(object = pbmcSmall_Seurat),
                            verbose = FALSE)
    
    pbmcSmall_Seurat <- FindNeighbors(pbmcSmall_Seurat, dims = 1:10)
    
    pbmcSmall_Seurat <- FindClusters(pbmcSmall_Seurat, verbose = FALSE)
    
    pbmcSmall_Seurat <- RunUMAP(pbmcSmall_Seurat, dims = 1:10)
    
    # Save the final Seurat object
    saveRDS(pbmcSmall_Seurat, file = "pbmcSmall_Seurat.rds")
    
    # Generate and save the UMAP plot
    pdf("umap_plot.pdf", width = 7, height = 6)
    print(DimPlot(pbmcSmall_Seurat, reduction = "umap"))
    dev.off()
    
    cat("Pipeline completed successfully. Outputs saved: 'pbmcSmall_Norm.rds', 'pbmcSmall_Seurat.rds', and 'umap_plot.pdf'.\n")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

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

    # HVG selection — count rows with high CV. Pass when 1000-3000 HVGs
    # (Stuart 2019 Cell Seurat v3 default range).
    .hvg_count <- NA_real_; .hvg_files <- character(0)
    for (.hvg_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
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

    # clustering QC — n_clusters ∈ [2,50] proxy (silhouette needs cluster pkg).
    .clu_n <- NA_real_
    for (.clu_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
      .clu_obj <- tryCatch(readRDS(.clu_rds), error = function(e) NULL)
      .clu_v <- NULL
      if (!is.null(.clu_obj)) {
        if (inherits(.clu_obj, "SingleCellExperiment")) {
          .clu_cd <- tryCatch(colData(.clu_obj), error = function(e) NULL)
          if (!is.null(.clu_cd)) {
            .clu_col <- intersect(c("cluster","clusters","seurat_clusters","label"), colnames(.clu_cd))
            if (length(.clu_col) > 0) .clu_v <- .clu_cd[[.clu_col[1]]]
          }
        } else if (inherits(.clu_obj, "Seurat")) {
          .clu_md <- tryCatch(.clu_obj@meta.data, error = function(e) NULL)
          if (!is.null(.clu_md)) {
            .clu_col <- intersect(c("seurat_clusters","cluster","clusters"), colnames(.clu_md))
            if (length(.clu_col) > 0) .clu_v <- .clu_md[[.clu_col[1]]]
          }
        }
      }
      if (!is.null(.clu_v) && length(.clu_v) > 0) {
        .clu_n <- length(unique(as.character(.clu_v[!is.na(.clu_v)]))); break
      }
    }
    .gates_by_label[["clustering QC"]] <- list(
      gate_row = "bioc_clustering_qc",
      metric_name = "n_clusters",
      metric_value = .clu_n,
      passes = isTRUE(is.finite(.clu_n) && .clu_n >= 2 && .clu_n <= 50),
      status = if (is.finite(.clu_n)) paste0("computed (n_clusters=", .clu_n, ")")
               else "not_computed (no SCE/Seurat with cluster column present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_DINO_STANDARD_MATRIX_NORMALIZATION_AND_SEURAT",
      domain  = "bioconductor",
      declared_qc_steps = c("low-count filtering", "highly-variable feature selection", "clustering QC"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_DINO_STANDARD_MATRIX_NORMALIZATION_AND_SEURAT":',
        paste0('    Dino: ', as.character(packageVersion('Dino')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_matrix_normalization_and_seurat.csv versions.yml
    """
}

workflow BIOC_DINO_STANDARD_MATRIX_NORMALIZATION_AND_SEURAT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pbmcSmall ] ]

    main:
    BIOC_DINO_STANDARD_MATRIX_NORMALIZATION_AND_SEURAT(ch_input)

    emit:
    tables   = BIOC_DINO_STANDARD_MATRIX_NORMALIZATION_AND_SEURAT.out.tables
    plots    = BIOC_DINO_STANDARD_MATRIX_NORMALIZATION_AND_SEURAT.out.plots
    objects  = BIOC_DINO_STANDARD_MATRIX_NORMALIZATION_AND_SEURAT.out.objects
    versions = BIOC_DINO_STANDARD_MATRIX_NORMALIZATION_AND_SEURAT.out.versions
}
