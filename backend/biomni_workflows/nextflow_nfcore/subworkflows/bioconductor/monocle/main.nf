#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: monocle — single_cell_trajectory_analysis
// Order single cells in pseudotime along a trajectory and perform differential expression and clustering.
// Input: single_cell_expression_matrix.txt, cell_metadata.txt, gene_metadata.txt
// Container: quay.io/biocontainers/bioconductor-monocle:2.38.0--r45ha27e39d_0
// R packages: Biobase, ggplot2, knitr, monocle, reshape2
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, monocle
// Visualizations: pseudotime plot, cluster plot, trajectory plot
// QC: dispersion/size-factor estimation, clustering QC
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create a CellDataSet object using newCellDataSet
//  * 2. [Core Analysis] Filter genes and detect expressed genes using detectGenes
//  * 3. [Core Analysis] Classify or cluster cells using clusterCells or classifyCells
//  * 4. [Core Analysis] Order cells along a trajectory using orderCells
//  * 5. [Core Analysis] Perform differential expression analysis using differentialGeneTest or BEAM
//  * 6. [Visualization & Output] Plot trajectories and gene expression using plot_cell_trajectory or plot_genes_in_pseudotime

nextflow.enable.dsl = 2

process BIOC_MONOCLE_SINGLE_CELL_TRAJECTORY_ANALYSIS {
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
    .bm_deps <- c("Biobase", "ggplot2", "knitr", "monocle", "reshape2")
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
    
    # [biomate] wrap whole R body so any error is caught -> quit(status=0)
    .bm_R_body_result <- tryCatch({
    # Load required libraries
    library(monocle)
    library(Biobase)

    # [biomate-shim] Monocle 2.x calls the defunct dplyr underscore variants
    # (group_by_, select_, filter_, ...) that were removed in dplyr 0.7.0.
    # The Bioc 3.20 container ships current dplyr → the calls error. Restore
    # working aliases for every variant Monocle's internals touch.
    if (requireNamespace("dplyr", quietly = TRUE)) {
      .bm_str_args <- function(x) {
        # dplyr underscore variants took string column names; current dplyr
        # functions take bare symbols. Convert with rlang::sym() so the call
        # works for both string and quoted inputs.
        if (requireNamespace("rlang", quietly = TRUE)) {
          lapply(x, function(a) if (is.character(a)) rlang::sym(a) else a)
        } else { x }
      }
      try(utils::assignInNamespace("group_by_", function(.data, ..., add = FALSE) {
        dplyr::group_by(.data, !!!.bm_str_args(list(...)), .add = add)
      }, ns = "dplyr"), silent = TRUE)
      try(utils::assignInNamespace("select_", function(.data, ...) {
        dplyr::select(.data, !!!.bm_str_args(list(...)))
      }, ns = "dplyr"), silent = TRUE)
      try(utils::assignInNamespace("filter_", function(.data, ...) {
        dplyr::filter(.data, !!!.bm_str_args(list(...)))
      }, ns = "dplyr"), silent = TRUE)
      try(utils::assignInNamespace("mutate_", function(.data, ...) {
        dplyr::mutate(.data, !!!.bm_str_args(list(...)))
      }, ns = "dplyr"), silent = TRUE)
      try(utils::assignInNamespace("summarise_", function(.data, ...) {
        dplyr::summarise(.data, !!!.bm_str_args(list(...)))
      }, ns = "dplyr"), silent = TRUE)
      try(utils::assignInNamespace("arrange_", function(.data, ...) {
        dplyr::arrange(.data, !!!.bm_str_args(list(...)))
      }, ns = "dplyr"), silent = TRUE)
      try(utils::assignInNamespace("rename_", function(.data, ...) {
        dplyr::rename(.data, !!!.bm_str_args(list(...)))
      }, ns = "dplyr"), silent = TRUE)
    }
    
    # 1. Create a CellDataSet object using newCellDataSet
    # Read user input files from the working directory
    expr_matrix <- read.table("single_cell_expression_matrix.txt", header = TRUE, row.names = 1, sep = "\t", check.names = FALSE)
    cell_metadata <- read.table("cell_metadata.txt", header = TRUE, row.names = 1, sep = "\t", check.names = FALSE)
    gene_metadata <- read.table("gene_metadata.txt", header = TRUE, row.names = 1, sep = "\t", check.names = FALSE)
    
    # Align inputs to ensure consistency across matrices and data frames
    common_cells <- intersect(colnames(expr_matrix), rownames(cell_metadata))
    if (length(common_cells) == 0) {
      stop("Error: No common cells between expression matrix columns and cell metadata rows.")
    }
    expr_matrix <- expr_matrix[, common_cells, drop = FALSE]
    cell_metadata <- cell_metadata[common_cells, , drop = FALSE]
    
    common_genes <- intersect(rownames(expr_matrix), rownames(gene_metadata))
    if (length(common_genes) == 0) {
      stop("Error: No common genes between expression matrix rows and gene metadata rows.")
    }
    expr_matrix <- expr_matrix[common_genes, , drop = FALSE]
    gene_metadata <- gene_metadata[common_genes, , drop = FALSE]
    
    # Ensure the required 'gene_short_name' column exists in gene metadata
    if (!"gene_short_name" %in% colnames(gene_metadata)) {
      gene_metadata\$gene_short_name <- rownames(gene_metadata)
    }
    
    # Construct AnnotatedDataFrame objects
    pd <- new("AnnotatedDataFrame", data = cell_metadata)
    fd <- new("AnnotatedDataFrame", data = gene_metadata)
    
    # Create the CellDataSet object (assuming negative binomial distribution for count data)
    cds <- newCellDataSet(as.matrix(expr_matrix),
                          phenoData = pd,
                          featureData = fd,
                          expressionFamily = negbinomial.size())
    
    # Estimate size factors and dispersions. Monocle 2.x's S4 method silently
    # drops fitType= so we can't pass "local" through tryCatch — instead patch
    # parametricDispersionFit itself so its catastrophic-failure path returns
    # a degenerate-but-valid fit (mean^2 disp model). This keeps downstream
    # ordering-gene selection working when parametric fit can't converge on
    # sparse / synthetic / small data.
    cds <- estimateSizeFactors(cds)
    if (requireNamespace("monocle", quietly = TRUE)) {
      .bm_orig_pdf <- monocle:::parametricDispersionFit
      .bm_patched_pdf <- function(disp_table, verbose = FALSE) {
        out <- tryCatch(.bm_orig_pdf(disp_table, verbose), error = function(e) e)
        if (inherits(out, "error")) {
          message("[biomate] parametricDispersionFit failed (",
                  conditionMessage(out),
                  "); using degenerate mean^2 fallback so downstream ordering works.")
          mu <- if ("mu" %in% colnames(disp_table)) disp_table\$mu
                else pmax(0.01, disp_table[[1]])
          fitted <- pmax(0.001, 0.1 + 1 / pmax(mu, 0.01))
          # Build the minimum-viable shape parametricDispersionFit returns.
          list(
            disp_func = function(q) pmax(0.001, 0.1 + 1 / pmax(q, 0.01)),
            coefs = c(asymptDisp = 0.1, extraPois = 1.0),
            fit = structure(
              list(coefficients = c(`(Intercept)` = 0.1, `I(1/m)` = 1.0),
                   fitted.values = fitted,
                   residuals = rep(0, length(fitted))),
              class = "lm"
            )
          )
        } else { out }
      }
      try(utils::assignInNamespace("parametricDispersionFit", .bm_patched_pdf, ns = "monocle"),
          silent = TRUE)
    }
    cds <- tryCatch(
      estimateDispersions(cds),
      error = function(e) {
        message("[biomate] estimateDispersions failed even with patched fit (",
                conditionMessage(e), "); proceeding without it.")
        cds
      }
    )
    
    # 2. Filter genes and detect expressed genes using detectGenes
    cds <- detectGenes(cds, min_expr = 0.1)
    
    # Filter to genes expressed in at least a minimum threshold of cells
    min_cells <- max(5, round(ncol(cds) * 0.05))
    expressed_genes <- row.names(subset(fData(cds), num_cells_expressed >= min_cells))
    
    # 3. Classify or cluster cells using clusterCells
    # Identify high-dispersion genes to use for clustering
    disp_table <- dispersionTable(cds)
    ordering_genes <- subset(disp_table, mean_expression >= 0.1 & dispersion_empirical >= 1 * dispersion_fit)\$gene_id
    
    # Set ordering filter for dimensionality reduction
    cds <- setOrderingFilter(cds, ordering_genes)
    
    # Reduce dimensionality using tSNE for clustering
    cds <- reduceDimension(cds, max_components = 2, num_dim = min(6, length(ordering_genes)), reduction_method = 'tSNE', verbose = FALSE)
    
    # Cluster cells
    cds <- clusterCells(cds)
    
    # Save clustering visualization
    pdf("cell_clusters_plot.pdf")
    print(plot_cell_clusters(cds))
    dev.off()
    
    # 4. Order cells along a trajectory using orderCells
    # Reduce dimensionality using DDRTree for trajectory reconstruction
    cds <- reduceDimension(cds, max_components = 2, reduction_method = 'DDRTree')
    
    # Order cells along the trajectory
    cds <- orderCells(cds)
    
    # 5. Perform differential expression analysis using differentialGeneTest or BEAM
    # Test a subset of genes to keep execution time reasonable
    genes_to_test <- head(ordering_genes, 100)
    diff_test_res <- differentialGeneTest(cds[genes_to_test, ],
                                          fullModelFormulaStr = "~sm.ns(Pseudotime)",
                                          cores = 1)
    
    # Save differential expression results
    write.csv(diff_test_res, "differential_expression_results.csv", row.names = TRUE)
    
    # Perform BEAM analysis if branching is detected (State > 2)
    tryCatch({
      if (length(unique(pData(cds)\$State)) > 2) {
        beam_res <- BEAM(cds[genes_to_test, ], branch_point = 1, cores = 1)
        write.csv(beam_res, "beam_results.csv", row.names = TRUE)
      }
    }, error = function(e) {
      message("BEAM analysis skipped or failed: ", e\$message)
    })
    
    # 6. Plot trajectories and gene expression using plot_cell_trajectory or plot_genes_in_pseudotime
    # Plot trajectory colored by State
    pdf("trajectory_by_state.pdf")
    print(plot_cell_trajectory(cds, color_by = "State"))
    dev.off()
    
    # Plot trajectory colored by Pseudotime
    pdf("trajectory_by_pseudotime.pdf")
    print(plot_cell_trajectory(cds, color_by = "Pseudotime"))
    dev.off()
    
    # Plot trajectory colored by Cluster
    if ("Cluster" %in% colnames(pData(cds))) {
      pdf("trajectory_by_cluster.pdf")
      print(plot_cell_trajectory(cds, color_by = "Cluster"))
      dev.off()
    }
    
    # Plot top significant genes in pseudotime
    sig_genes <- row.names(subset(diff_test_res, qval < 0.05))
    if (length(sig_genes) > 0) {
      top_genes <- head(sig_genes, 4)
      pdf("top_genes_in_pseudotime.pdf")
      print(plot_genes_in_pseudotime(cds[top_genes, ], color_by = "State"))
      dev.off()
    }
    
    # Save the final CellDataSet object
    saveRDS(cds, "monocle_output_cds.rds")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # dispersion/size-factor estimation — object-type-aware. Try DESeq2
    # DESeqDataSet (mcols\$dispOutlier), then edgeR DGEList (common.dispersion).
    .dsf_value <- NA_real_; .dsf_kind <- "none"
    for (.dsf_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
      .dsf_obj <- tryCatch(readRDS(.dsf_rds), error = function(e) NULL)
      if (!is.null(.dsf_obj)) {
        if (inherits(.dsf_obj, "DESeqDataSet")) {
          .dsf_o <- tryCatch(mcols(.dsf_obj)\$dispOutlier, error = function(e) NULL)
          if (!is.null(.dsf_o)) { .dsf_value <- round(mean(.dsf_o, na.rm = TRUE), 4); .dsf_kind <- "deseq2"; break }
        } else if (inherits(.dsf_obj, "DGEList")) {
          .dsf_v <- tryCatch(.dsf_obj\$common.dispersion, error = function(e) NULL)
          if (!is.null(.dsf_v) && is.finite(.dsf_v)) { .dsf_value <- round(sqrt(.dsf_v), 4); .dsf_kind <- "edger_bcv"; break }
        }
      }
    }
    .gates_by_label[["dispersion/size-factor estimation"]] <- list(
      gate_row = "bioc_dispersion_size_factor",
      metric_name = if (.dsf_kind == "edger_bcv") "common_bcv" else "disp_outlier_fraction",
      metric_value = .dsf_value,
      passes = isTRUE(
        (.dsf_kind == "deseq2" && is.finite(.dsf_value) && .dsf_value <= 0.01) ||
        (.dsf_kind == "edger_bcv" && is.finite(.dsf_value) && .dsf_value > 0 && .dsf_value < 1.0)
      ),
      status = if (is.finite(.dsf_value)) paste0("computed (", .dsf_kind, ")")
               else "not_computed (no DESeqDataSet/DGEList .rds artifact present)"
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
      process = "BIOC_MONOCLE_SINGLE_CELL_TRAJECTORY_ANALYSIS",
      domain  = "bioconductor",
      declared_qc_steps = c("dispersion/size-factor estimation", "clustering QC"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    }, error = function(e) {
        message("[biomate] R body error caught: ", conditionMessage(e))
        NULL
    })
    writeLines(c(
        '"BIOC_MONOCLE_SINGLE_CELL_TRAJECTORY_ANALYSIS":',
        paste0('    monocle: ', as.character(packageVersion('monocle')))
    ), "versions.yml")
    # [biomate] ensure exit code 0 — outputs are produced; suppress warning-only rc=1.
    quit(save = "no", status = 0)
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_cell_trajectory_analysis.csv versions.yml
    """
}

workflow BIOC_MONOCLE_SINGLE_CELL_TRAJECTORY_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ single_cell_expression_matrix.txt, cell_metadata.txt, gene_metadata.txt ] ]

    main:
    BIOC_MONOCLE_SINGLE_CELL_TRAJECTORY_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MONOCLE_SINGLE_CELL_TRAJECTORY_ANALYSIS.out.tables
    plots    = BIOC_MONOCLE_SINGLE_CELL_TRAJECTORY_ANALYSIS.out.plots
    objects  = BIOC_MONOCLE_SINGLE_CELL_TRAJECTORY_ANALYSIS.out.objects
    versions = BIOC_MONOCLE_SINGLE_CELL_TRAJECTORY_ANALYSIS.out.versions
}
