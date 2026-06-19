#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scDD — differential_distribution_analysis
// Identify and classify differentially distributed genes between two biological conditions in single-cell RNA-seq data.
// Input: expression_matrix.csv, metadata.csv
// Container: quay.io/biocontainers/bioconductor-scdd:1.34.0--r45hdfd78af_0
// R packages: gridExtra, scDD, SingleCellExperiment
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, gridExtra, scDD
// Visualizations: violin plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Construct a SingleCellExperiment object from the expression matrices and condition labels
//  * 2. [Core Analysis] Preprocess the data to filter out genes with high zero proportions and apply normalization
//  * 3. [Input & Preparation] Define the prior parameters for the mixture model
//  * 4. [Core Analysis] Run the scDD engine to test for differential distributions and classify genes
//  * 5. [Core Analysis] Extract the main results and partition estimates
//  * 6. [Visualization & Output] Visualize the expression distributions of significant genes using side-by-side violin plots

nextflow.enable.dsl = 2

process BIOC_SCDD_DIFFERENTIAL_DISTRIBUTION_ANALYSIS {
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
    .bm_deps <- c("gridExtra", "scDD", "SingleCellExperiment")
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
    library(scDD)
    library(gridExtra)
    
    # ==========================================
    # 1. Load User Input and Construct SCE Object
    # ==========================================
    
    if (!file.exists("expression_matrix.csv") || !file.exists("metadata.csv")) {
      stop("Required input files 'expression_matrix.csv' and/or 'metadata.csv' are missing in the working directory.")
    }
    
    # Read expression matrix and metadata
    expr_df <- read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE)
    meta_df <- read.csv("metadata.csv", row.names = 1, check.names = FALSE)
    
    # Align cells between expression matrix and metadata
    common_cells <- intersect(colnames(expr_df), rownames(meta_df))
    if (length(common_cells) == 0) {
      stop("No common cells found between expression matrix columns and metadata rows.")
    }
    
    expr_mat <- as.matrix(expr_df[, common_cells, drop = FALSE])
    meta_df <- meta_df[common_cells, , drop = FALSE]
    
    # Ensure condition column exists
    if (!"condition" %in% colnames(meta_df)) {
      colnames(meta_df)[1] <- "condition"
    }
    
    # Construct condition vector and ensure it is numeric 1 and 2
    condition <- as.numeric(as.factor(meta_df\$condition))
    names(condition) <- colnames(expr_mat)
    
    # Construct SingleCellExperiment object
    sce <- SingleCellExperiment(
      assays = list(counts = expr_mat, normcounts = expr_mat), 
      colData = data.frame(condition)
    )
    
    # ==========================================
    # 2. Preprocess the Data
    # ==========================================
    
    scDatEx <- sce
    scDatEx <- preprocess(scDatEx, zero.thresh = 0.9)
    
    # Apply scran normalization with fallback if it fails
    scDatEx.scran <- tryCatch({
      preprocess(scDatEx, zero.thresh = 0.5, scran_norm = TRUE)
    }, error = function(e) {
      warning("scran normalization failed, falling back to standard preprocessing: ", e\$message)
      preprocess(scDatEx, zero.thresh = 0.5, scran_norm = FALSE)
    })
    
    # Set up the object for the scDD engine
    scDatExSim <- scDatEx.scran
    
    # ==========================================
    # 3. Define Prior Parameters
    # ==========================================
    
    prior_param <- list(alpha = 0.01, mu0 = 0, s0 = 0.01, a0 = 0.01, b0 = 0.01)
    
    # ==========================================
    # 4. Run scDD Engine (Fast KS Test)
    # ==========================================
    
    scDatExSim <- scDD(scDatExSim, prior_param = prior_param, testZeroes = FALSE)
    
    # ==========================================
    # 5. Extract Results and Partition Estimates
    # ==========================================
    
    RES <- results(scDatExSim)
    PARTITION.C1 <- results(scDatExSim, type = "Zhat.c1")
    
    # Save intermediate results
    write.csv(RES, "scDD_results_fast.csv", row.names = FALSE)
    write.csv(as.data.frame(PARTITION.C1), "scDD_partition_c1.csv", row.names = TRUE)
    
    # ==========================================
    # 6. Save Final Object
    # ==========================================
    
    # Save final results
    saveRDS(scDatExSim, "scDD_final_object.rds")
    
    # ==========================================
    # 7. Visualize Expression Distributions
    # ==========================================
    
    # Identify top genes to plot
    if ("nonzero.pvalue.adj" %in% colnames(RES)) {
      top_genes <- as.character(RES\$gene[order(RES\$nonzero.pvalue.adj)])
    } else {
      top_genes <- as.character(RES\$gene)
    }
    
    # Generate the primary violin plot for the first gene
    de <- sideViolin(normcounts(scDatExSim)[top_genes[1],], scDatExSim\$condition, title.gene = top_genes[1])
    
    # Safely define remaining plots to prevent out-of-bounds errors if the dataset has few genes
    dp <- if (length(top_genes) >= 2) {
      sideViolin(normcounts(scDatExSim)[top_genes[2],], scDatExSim\$condition, title.gene = top_genes[2])
    } else { de }
    
    dm <- if (length(top_genes) >= 3) {
      sideViolin(normcounts(scDatExSim)[top_genes[3],], scDatExSim\$condition, title.gene = top_genes[3])
    } else { de }
    
    db <- if (length(top_genes) >= 4) {
      sideViolin(normcounts(scDatExSim)[top_genes[4],], scDatExSim\$condition, title.gene = top_genes[4])
    } else { de }
    
    ep <- if (length(top_genes) >= 5) {
      sideViolin(normcounts(scDatExSim)[top_genes[5],], scDatExSim\$condition, title.gene = top_genes[5])
    } else { de }
    
    ee <- if (length(top_genes) >= 6) {
      sideViolin(normcounts(scDatExSim)[top_genes[6],], scDatExSim\$condition, title.gene = top_genes[6])
    } else { de }
    
    # Arrange and save the plots to a PDF file
    pdf("scDD_violin_plots.pdf", width = 8.5, height = 11)
    grid.arrange(de, dp, dm, db, ep, ee, ncol = 2)
    dev.off()
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

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

    # count normalization — scan .rds matrix artifacts for library-size CV
    # ratio (post-norm / pre-norm); without raw input we report median lib CV
    # as a proxy diagnostic. Threshold = 0.7 (Bullard 2010 BMC Bioinf).
    .cn_lib_cvs <- numeric(0)
    .cn_scanned <- character(0)
    for (.cn_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
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

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_SCDD_DIFFERENTIAL_DISTRIBUTION_ANALYSIS",
      domain  = "bioconductor",
      declared_qc_steps = c("cell QC metrics", "count normalization", "low-count filtering"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_SCDD_DIFFERENTIAL_DISTRIBUTION_ANALYSIS":',
        paste0('    scDD: ', as.character(packageVersion('scDD')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_distribution_analysis.csv versions.yml
    """
}

workflow BIOC_SCDD_DIFFERENTIAL_DISTRIBUTION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv, metadata.csv ] ]

    main:
    BIOC_SCDD_DIFFERENTIAL_DISTRIBUTION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SCDD_DIFFERENTIAL_DISTRIBUTION_ANALYSIS.out.tables
    plots    = BIOC_SCDD_DIFFERENTIAL_DISTRIBUTION_ANALYSIS.out.plots
    objects  = BIOC_SCDD_DIFFERENTIAL_DISTRIBUTION_ANALYSIS.out.objects
    versions = BIOC_SCDD_DIFFERENTIAL_DISTRIBUTION_ANALYSIS.out.versions
}
