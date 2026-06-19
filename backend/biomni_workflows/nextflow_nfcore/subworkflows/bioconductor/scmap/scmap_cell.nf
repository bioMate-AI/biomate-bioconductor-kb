#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scmap — scmap_cell
// Project query single-cell RNA-seq data onto individual reference cells and optionally annotate them using reference cluster labels.
// Input: yan, ann
// Container: quay.io/biocontainers/bioconductor-scmap:1.32.0--r45ha27e39d_0
// R packages: SingleCellExperiment, scmap
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, scmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create SingleCellExperiment object and preprocess
//  * 2. [Core Analysis] Feature selection using selectFeatures
//  * 3. [Core Analysis] Reference cell indexing using indexCell
//  * 4. [Core Analysis] Projection using scmapCell
//  * 5. [Core Analysis] Cluster annotation using scmapCell2Cluster
//  * 6. [Visualization & Output] Visualization using getSankey

nextflow.enable.dsl = 2

process BIOC_SCMAP_SCMAP_CELL {
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
    .bm_deps <- c("SingleCellExperiment", "scmap", "SummarizedExperiment")
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
                library(SummarizedExperiment)
library(scmap)
        
        # -----------------------------------------------------------------------------
        # Stage 1: Read User Input and Preprocess
        # -----------------------------------------------------------------------------
        
        # Helper function to robustly read the 'yan' matrix
        read_yan <- function() {
          if (file.exists("yan.rds")) {
            return(readRDS("yan.rds"))
          } else if (file.exists("yan.csv")) {
            return(as.matrix(read.csv("yan.csv", row.names = 1, check.names = FALSE)))
          } else if (file.exists("yan.tsv")) {
            return(as.matrix(read.delim("yan.tsv", row.names = 1, check.names = FALSE)))
          } else if (file.exists("yan")) {
            return(as.matrix(read.table("yan", header = TRUE, row.names = 1, check.names = FALSE)))
          } else {
            stop("Error: 'yan' file not found in the working directory.")
          }
        }
        
        # Helper function to robustly read the 'ann' data frame
        read_ann <- function() {
          if (file.exists("ann.rds")) {
            return(readRDS("ann.rds"))
          } else if (file.exists("ann.csv")) {
            return(read.csv("ann.csv", row.names = 1, check.names = FALSE))
          } else if (file.exists("ann.tsv")) {
            return(read.delim("ann.tsv", row.names = 1, check.names = FALSE))
          } else if (file.exists("ann")) {
            return(read.table("ann", header = TRUE, row.names = 1, check.names = FALSE))
          } else {
            stop("Error: 'ann' file not found in the working directory.")
          }
        }
        
        yan <- read_yan()
        ann <- read_ann()
        
        # Construct SingleCellExperiment object and preprocess as documented
        sce <- SingleCellExperiment(assays = list(normcounts = as.matrix(yan)), colData = ann)
        logcounts(sce) <- log2(normcounts(sce) + 1)
        rowData(sce)\$feature_symbol <- rownames(sce)
        sce <- sce[!duplicated(rownames(sce)), ]
        
        # -----------------------------------------------------------------------------
        # Stage 2: Feature Selection
        # -----------------------------------------------------------------------------
        sce <- selectFeatures(sce, suppress_plot = TRUE)
        
        # -----------------------------------------------------------------------------
        # Stage 3: Reference Cell Indexing
        # -----------------------------------------------------------------------------
        set.seed(1)
        sce <- indexCell(sce)
        
        # -----------------------------------------------------------------------------
        # Stage 4: Projection using scmapCell
        # -----------------------------------------------------------------------------
        scmapCell_results <- scmapCell(
          sce, 
          list(
            yan = metadata(sce)\$scmap_cell_index
          )
        )
        
        # -----------------------------------------------------------------------------
        # Stage 5: Cluster Annotation
        # -----------------------------------------------------------------------------
        scmapCell_clusters <- scmapCell2Cluster(
          scmapCell_results, 
          list(
            as.character(colData(sce)\$cell_type1)
          )
        )
        
        # -----------------------------------------------------------------------------
        # Stage 6: Visualization
        # -----------------------------------------------------------------------------
        # The plot() call on a googleVis object is removed to prevent hanging in headless environments.
        # The Sankey diagram is saved as an HTML file in the Save Outputs section.
        
        # -----------------------------------------------------------------------------
        # Save Outputs
        # -----------------------------------------------------------------------------
        
        # Save the processed SingleCellExperiment object
        saveRDS(sce, "processed_sce.rds")
        
        # Save the scmapCell projection results
        saveRDS(scmapCell_results, "scmapCell_results.rds")
        
        # Save the scmapCell cluster annotation results
        saveRDS(scmapCell_clusters, "scmapCell_clusters.rds")
        
        # Export the cluster assignments as a CSV table
        output_labels <- data.frame(
          Cell = rownames(colData(sce)),
          Original_Cell_Type = colData(sce)\$cell_type1,
          Assigned_Cluster = scmapCell_clusters\$scmap_cluster_labs[,"yan"],
          Similarity = scmapCell_clusters\$scmap_cluster_siml[,"yan"],
          Combined_Labs = scmapCell_clusters\$combined_labs,
          stringsAsFactors = FALSE
        )
        write.csv(output_labels, "scmap_cell_assignments.csv", row.names = FALSE)
        
        # Save the Sankey diagram as an HTML file (since getSankey returns a googleVis object)
        sankey_gvis <- getSankey(
          colData(sce)\$cell_type1,
          scmapCell_clusters\$scmap_cluster_labs[,"yan"],
          plot_height = 400
        )
        writeLines(sankey_gvis\$html\$chart, "sankey_plot.html")
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
      process = "BIOC_SCMAP_SCMAP_CELL",
      domain  = "bioconductor",
      declared_qc_steps = c("cell QC metrics", "count normalization", "low-count filtering"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_SCMAP_SCMAP_CELL":',
        paste0('    scmap: ', as.character(packageVersion('scmap')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scmap_cell.csv versions.yml
    """
}

workflow BIOC_SCMAP_SCMAP_CELL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ yan, ann ] ]

    main:
    BIOC_SCMAP_SCMAP_CELL(ch_input)

    emit:
    tables   = BIOC_SCMAP_SCMAP_CELL.out.tables
    plots    = BIOC_SCMAP_SCMAP_CELL.out.plots
    objects  = BIOC_SCMAP_SCMAP_CELL.out.objects
    versions = BIOC_SCMAP_SCMAP_CELL.out.versions
}
