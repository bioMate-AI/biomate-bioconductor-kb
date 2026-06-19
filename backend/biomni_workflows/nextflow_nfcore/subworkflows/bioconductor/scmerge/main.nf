#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scMerge — sc_merge_v1
// Integrate single-cell RNA-seq batches using the original k-means-based scMerge algorithm.
// Input: example_sce, segList_ensemblGeneID
// Container: quay.io/biocontainers/bioconductor-scmerge:1.26.0--r45hdfd78af_0
// R packages: BiocParallel, DelayedArray, HDF5Array, Matrix, BiocSingular, ggplot2, scater, scMerge, SingleCellExperiment
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, BiocSingular, DelayedArray, HDF5Array, Matrix, SingleCellExperiment, ggplot2, scMerge, scater
// Visualizations: PCA plot
// QC: diagnostic MA/PCA QC, low-count filtering, cell QC metrics
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load data and negative controls
//  * 2. [Core Analysis] Run unsupervised, supervised, or semi-supervised scMerge
//  * 3. [Core Analysis] Run fast scMerge with approximated SVD for large datasets
//  * 4. [Core Analysis] Run parallelized scMerge
//  * 5. [Core Analysis] Run scMerge with sparse or HDF5-backed matrices

nextflow.enable.dsl = 2

process BIOC_SCMERGE_SC_MERGE_V1 {
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
    .bm_deps <- c("BiocParallel", "DelayedArray", "HDF5Array", "Matrix", "BiocSingular", "ggplot2", "scater", "scMerge", "SingleCellExperiment", "SummarizedExperiment")
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
    library(scMerge)
    library(SummarizedExperiment)
    library(scater)
    library(BiocSingular)
    library(BiocParallel)
    library(Matrix)
    library(DelayedArray)
    library(HDF5Array)
    library(ggplot2)
    
    # ==========================================
    # STAGE 1: Load data and negative controls
    # ==========================================
    
    # Helper function to read input files robustly (with or without .rds extension)
    read_input <- function(filename) {
      if (file.exists(filename)) {
        return(readRDS(filename))
      } else if (file.exists(paste0(filename, ".rds"))) {
        return(readRDS(paste0(filename, ".rds")))
      } else {
        stop(paste("Required input file not found:", filename))
      }
    }
    
    # Read the user-provided input files
    example_sce <- read_input("example_sce")
    segList_ensemblGeneID <- read_input("segList_ensemblGeneID")
    
    # Extract stably expressed genes robustly (handles both flat vectors and nested lists)
    ctl_genes <- as.character(unlist(segList_ensemblGeneID))
    
    # Determine kmeansK dynamically based on the number of unique cell types per batch
    kmeansK_vec <- as.vector(rowSums(table(example_sce\$batch, example_sce\$cellTypes) > 0))
    
    # Determine a generic cell type for semi-supervised scMerge
    generic_cell_type <- example_sce\$cellTypes[1]
    
    # ==========================================
    # STAGE 2: Run unsupervised, supervised, or semi-supervised scMerge
    # ==========================================
    
    # Unsupervised scMerge
    scMerge_unsupervised <- scMerge(
      sce_combine = example_sce, 
      ctl = ctl_genes,
      kmeansK = kmeansK_vec,
      assay_name = "scMerge_unsupervised")
    
    # Unsupervised scMerge using all cells
    scMerge_unsupervised_all <- scMerge(
      sce_combine = example_sce, 
      ctl = ctl_genes,
      kmeansK = kmeansK_vec,
      assay_name = "scMerge_unsupervised_all",
      replicate_prop = 1)
    
    # Supervised scMerge
    scMerge_supervised <- scMerge(
      sce_combine = example_sce,
      ctl = ctl_genes,
      kmeansK = kmeansK_vec,
      assay_name = "scMerge_supervised",
      cell_type = example_sce\$cellTypes)
    
    # Semi-supervised scMerge I
    scMerge_semisupervised1 <- scMerge(
      sce_combine = example_sce,
      ctl = ctl_genes,
      kmeansK = kmeansK_vec,
      assay_name = "scMerge_semisupervised1",
      cell_type = example_sce\$cellTypes,
      cell_type_inc = which(example_sce\$cellTypes == generic_cell_type), 
      cell_type_match = FALSE)
    
    # Semi-supervised scMerge II
    scMerge_semisupervised2 <- scMerge(
      sce_combine = example_sce,
      ctl = ctl_genes,
      kmeansK = kmeansK_vec,
      assay_name = "scMerge_semisupervised2",
      cell_type = example_sce\$cellTypes,
      cell_type_inc = NULL,
      cell_type_match = TRUE)
    
    # ==========================================
    # STAGE 3: Run fast scMerge with SVD
    # ==========================================
    
    library(BiocSingular)
    scMerge_fast <- scMerge(
      sce_combine = example_sce, 
      ctl = ctl_genes,
      kmeansK = kmeansK_vec,
      assay_name = "scMerge_fast", 
      BSPARAM = IrlbaParam(), 
      svd_k = 20)
    
    # ==========================================
    # STAGE 4: Run parallelized scMerge
    # ==========================================
    
    library(BiocParallel)
    # Wrap in tryCatch to handle OS-specific parallelization constraints gracefully
    tryCatch({
      scMerge_parallel <- scMerge(
        sce_combine = example_sce,
        ctl = ctl_genes,
        kmeansK = kmeansK_vec,
        assay_name = "scMerge_parallel",
        BPPARAM = MulticoreParam(workers = 2)
      )
    }, error = function(e) {
      message("MulticoreParam failed or is unsupported on this OS. Falling back to SerialParam.")
      scMerge_parallel <<- scMerge(
        sce_combine = example_sce,
        ctl = ctl_genes,
        kmeansK = kmeansK_vec,
        assay_name = "scMerge_parallel",
        BPPARAM = SerialParam()
      )
    })
    
    # ==========================================
    # STAGE 5: Run scMerge with sparse or HDF5-backed matrices
    # ==========================================
    
    # Sparse array input
    library(Matrix)
    library(DelayedArray)
    sparse_input = example_sce
    assay(sparse_input, "counts") = as(counts(sparse_input), "dgCMatrix")
    assay(sparse_input, "logcounts") = as(logcounts(sparse_input), "dgCMatrix")
    scMerge_sparse = scMerge(
      sce_combine = sparse_input,
      ctl = ctl_genes,
      kmeansK = kmeansK_vec,
      assay_name = "scMerge_sparse")
    
    # Out-of-memory computations (HDF5Array)
    library(HDF5Array)
    library(DelayedArray)
    options(DelayedArray.verbose.block.processing=TRUE)
    hdf5_input = example_sce
    assay(hdf5_input, "counts") = as(counts(hdf5_input), "HDF5Array")
    assay(hdf5_input, "logcounts") = as(logcounts(hdf5_input), "HDF5Array")
    scMerge_hdf5 = scMerge(
      sce_combine = hdf5_input,
      ctl = ctl_genes,
      kmeansK = kmeansK_vec,
      assay_name = "scMerge_hdf5")
    
    # ==========================================
    # STAGE 6: Save Outputs and Generate Plots
    # ==========================================
    
    # Save RDS objects of the integrated SingleCellExperiment objects
    saveRDS(scMerge_unsupervised, "scMerge_unsupervised.rds")
    saveRDS(scMerge_unsupervised_all, "scMerge_unsupervised_all.rds")
    saveRDS(scMerge_supervised, "scMerge_supervised.rds")
    saveRDS(scMerge_semisupervised1, "scMerge_semisupervised1.rds")
    saveRDS(scMerge_semisupervised2, "scMerge_semisupervised2.rds")
    saveRDS(scMerge_fast, "scMerge_fast.rds")
    saveRDS(scMerge_parallel, "scMerge_parallel.rds")
    saveRDS(scMerge_sparse, "scMerge_sparse.rds")
    saveRDS(scMerge_hdf5, "scMerge_hdf5.rds")
    
    # Generate diagnostic PCA plots to evaluate integration performance
    pdf("scMerge_integration_plots.pdf", width = 10, height = 8)
    
    # 1. Original PCA (Uncorrected)
    example_sce <- runPCA(example_sce, exprs_values = "logcounts")
    p_orig <- scater::plotPCA(example_sce, colour_by = "cellTypes", shape_by = "batch") + 
      labs(title = "Original Data (Uncorrected Batch Effects)")
    print(p_orig)
    
    # 2. Unsupervised scMerge PCA
    scMerge_unsupervised <- runPCA(scMerge_unsupervised, exprs_values = "scMerge_unsupervised")
    p_unsupervised <- scater::plotPCA(scMerge_unsupervised, colour_by = "cellTypes", shape_by = "batch") + 
      labs(title = "scMerge Unsupervised Integration")
    print(p_unsupervised)
    
    # 3. Supervised scMerge PCA
    scMerge_supervised <- runPCA(scMerge_supervised, exprs_values = "scMerge_supervised")
    p_supervised <- scater::plotPCA(scMerge_supervised, colour_by = "cellTypes", shape_by = "batch") + 
      labs(title = "scMerge Supervised Integration")
    print(p_supervised)
    
    # 4. Fast scMerge PCA
    scMerge_fast <- runPCA(scMerge_fast, exprs_values = "scMerge_fast")
    p_fast <- scater::plotPCA(scMerge_fast, colour_by = "cellTypes", shape_by = "batch") + 
      labs(title = "Fast scMerge Integration (Approximated SVD)")
    print(p_fast)
    
    dev.off()
    
    message("scMerge pipeline completed successfully. Outputs saved to working directory.")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # diagnostic MA/PCA QC — PC1 variance explained on any large matrix.
    # Pass when PC1 > 10% (Risso 2014 RUV-seq diagnostic).
    .pca_pc1 <- NA_real_; .pca_files <- character(0)
    for (.pca_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .pca_obj <- tryCatch(readRDS(.pca_rds), error = function(e) NULL)
      .pca_mat <- if (is.matrix(.pca_obj) || is.data.frame(.pca_obj)) .pca_obj else NULL
      if (!is.null(.pca_mat) && ncol(.pca_mat) >= 3 && nrow(.pca_mat) >= 100) {
        .pca_m <- suppressWarnings(as.matrix(.pca_mat))
        .pca_kept <- apply(.pca_m, 1, function(r) all(is.finite(r)) && var(r) > 0)
        if (sum(.pca_kept) >= 50) {
          .pca_fit <- tryCatch(prcomp(t(.pca_m[.pca_kept, , drop = FALSE])), error = function(e) NULL)
          if (!is.null(.pca_fit)) {
            .pca_vars <- (.pca_fit\$sdev^2) / sum(.pca_fit\$sdev^2)
            .pca_pc1 <- round(.pca_vars[1] * 100, 2); .pca_files <- c(.pca_files, .pca_rds); break
          }
        }
      }
    }
    .gates_by_label[["diagnostic MA/PCA QC"]] <- list(
      gate_row = "bioc_diagnostic_ma_pca_qc",
      metric_name = "pc1_var_explained",
      metric_value = .pca_pc1,
      passes = isTRUE(is.finite(.pca_pc1) && .pca_pc1 > 10),
      status = if (is.finite(.pca_pc1)) paste0("computed (PC1=", .pca_pc1, "%)")
               else "not_computed (no large numeric matrix .rds artifact present)"
    )

    # low-count filtering — fraction of genes retained (heuristic on matrix artifacts).
    # Pass band 30-60% per Chen 2016 F1000 (edgeR filterByExpr convention).
    .lcf_kept_fractions <- numeric(0)
    .lcf_scanned <- character(0)
    for (.lcf_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
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

    # cell QC metrics — defensive cell-count + per-cell summary from any
    # matrix artifact. Pass when columns (cells) ≥ 50 and rows (features) ≥ 200
    # (Luecken & Theis 2019 single-cell QC floor).
    .cqc_ncells <- NA_real_; .cqc_nfeats <- NA_real_; .cqc_files <- character(0)
    for (.cqc_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
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

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_SCMERGE_SC_MERGE_V1",
      domain  = "bioconductor",
      declared_qc_steps = c("diagnostic MA/PCA QC", "low-count filtering", "cell QC metrics"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_SCMERGE_SC_MERGE_V1":',
        paste0('    scMerge: ', as.character(packageVersion('scMerge')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sc_merge_v1.csv versions.yml
    """
}

workflow BIOC_SCMERGE_SC_MERGE_V1_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ example_sce, segList_ensemblGeneID ] ]

    main:
    BIOC_SCMERGE_SC_MERGE_V1(ch_input)

    emit:
    tables   = BIOC_SCMERGE_SC_MERGE_V1.out.tables
    plots    = BIOC_SCMERGE_SC_MERGE_V1.out.plots
    objects  = BIOC_SCMERGE_SC_MERGE_V1.out.objects
    versions = BIOC_SCMERGE_SC_MERGE_V1.out.versions
}
