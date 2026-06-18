#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scMerge — sc_merge_v2_hierarchical
// Perform multi-level hierarchical batch integration using scMerge2h.
// Input: example_sce, segList_ensemblGeneID
// Container: quay.io/biocontainers/bioconductor-scmerge:1.26.0--r45hdfd78af_0
// R packages: SingleCellExperiment, scMerge, scater
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, scMerge, scater
// Visualizations: PCA plot
// QC: diagnostic MA/PCA QC, cell QC metrics
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Construct hierarchical index list
//  * 2. [Input & Preparation] Construct batch information list
//  * 3. [Core Analysis] Run scMerge2h with specified ruvK for each level
//  * 4. [Core Analysis] Extract the final level adjusted matrix

nextflow.enable.dsl = 2

process BIOC_SCMERGE_SC_MERGE_V2_HIERARCHICAL {
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
    .bm_deps <- c("SingleCellExperiment", "scMerge", "scater", "SummarizedExperiment")
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
        suppressPackageStartupMessages({
             library(SummarizedExperiment)
       library(scMerge)
          library(scater)
        })
        
        # Helper function to read input files from the working directory
        read_input <- function(filename) {
          if (file.exists(filename)) {
            return(readRDS(filename))
          } else if (file.exists(paste0(filename, ".rds"))) {
            return(readRDS(paste0(filename, ".rds")))
          } else {
            stop(paste("Required input file not found:", filename))
          }
        }
        
        # 1. Read user input files
        example_sce <- read_input("example_sce")
        segList_ensemblGeneID <- read_input("segList_ensemblGeneID")
        
        # 2. Construct hierarchical index list
        h_idx_list <- list(level1 = split(seq_len(ncol(example_sce)), example_sce\$batch),
                           level2 = list(seq_len(ncol(example_sce))))
        
        # 3. Construct batch information list
        batch_list <- list(level1 = split(example_sce\$sample, example_sce\$batch),
                           level2 = list(example_sce\$batch))
        
        # 4. Run scMerge2h with specified ruvK for each level
        scMerge2_res <- scMerge2h(exprsMat = logcounts(example_sce),
                                  batch_list = batch_list,
                                  h_idx_list = h_idx_list,
                                  ctl = unlist(segList_ensemblGeneID),
                                  ruvK_list = c(2, 5),
                                  verbose = FALSE)
        
        # 5. Extract the final level adjusted matrix
        assay(example_sce, "scMerge2") <- scMerge2_res[[length(h_idx_list)]]
        
        # 6. Write outputs
        # Save the integrated SingleCellExperiment object
        saveRDS(example_sce, "integrated_example_sce.rds")
        
        # Save the adjusted matrix as a CSV file
        write.csv(as.matrix(assay(example_sce, "scMerge2")), "scMerge2_adjusted_matrix.csv", row.names = TRUE)
        
        # Generate and save PCA plot of the integrated data
        pdf("scMerge2_pca_plot.pdf", width = 7, height = 6)
        set.seed(2022)
        example_sce <- scater::runPCA(example_sce, exprs_values = "scMerge2")
        p <- scater::plotPCA(example_sce, colour_by = "sample", shape_by = "batch")
        print(p)
        dev.off()
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
      process = "BIOC_SCMERGE_SC_MERGE_V2_HIERARCHICAL",
      domain  = "bioconductor",
      declared_qc_steps = c("diagnostic MA/PCA QC", "cell QC metrics"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_SCMERGE_SC_MERGE_V2_HIERARCHICAL":',
        paste0('    scMerge: ', as.character(packageVersion('scMerge')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sc_merge_v2_hierarchical.csv versions.yml
    """
}

workflow BIOC_SCMERGE_SC_MERGE_V2_HIERARCHICAL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ example_sce, segList_ensemblGeneID ] ]

    main:
    BIOC_SCMERGE_SC_MERGE_V2_HIERARCHICAL(ch_input)

    emit:
    tables   = BIOC_SCMERGE_SC_MERGE_V2_HIERARCHICAL.out.tables
    plots    = BIOC_SCMERGE_SC_MERGE_V2_HIERARCHICAL.out.plots
    objects  = BIOC_SCMERGE_SC_MERGE_V2_HIERARCHICAL.out.objects
    versions = BIOC_SCMERGE_SC_MERGE_V2_HIERARCHICAL.out.versions
}
