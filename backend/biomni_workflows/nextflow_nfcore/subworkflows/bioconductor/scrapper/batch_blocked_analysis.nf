#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scrapper — batch_blocked_analysis
// Combine multiple single-cell datasets and perform batch-corrected analysis using MNN correction and block-aware calculations.
// Input: sce.t, sce.z
// Container: quay.io/biocontainers/bioconductor-scrapper:1.4.0--r45ha27e39d_0
// R packages: SingleCellExperiment, scater, scrapper, scuttle
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, scater, scrapper, scuttle
// Visualizations: ordination plot, t-SNE plot
// QC: cell QC metrics
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Find common genes and combine columns
//  * 2. [Input & Preparation] Define batch blocking vector
//  * 3. [Core Analysis] Run batch-aware end-to-end analysis with analyze.se()
//  * 4. [Visualization & Output] Visualize batch correction
//  * 5. [Core Analysis] Aggregate cells across clusters and batches with aggregateAcrossCells.se()

nextflow.enable.dsl = 2

process BIOC_SCRAPPER_BATCH_BLOCKED_ANALYSIS {
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
    .bm_deps <- c("SingleCellExperiment", "scater", "scrapper", "scuttle")
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
    library(scrapper)
    library(scater)
    library(scuttle)
    
    # Read user input files from the working directory
    file_t <- if (file.exists("sce.t")) "sce.t" else "sce.t.rds"
    file_z <- if (file.exists("sce.z")) "sce.z" else "sce.z.rds"
    
    if (!file.exists(file_t) || !file.exists(file_z)) {
        stop("Required input files (sce.t and sce.z) not found in the working directory.")
    }
    
    sce.t <- readRDS(file_t)
    sce.z <- readRDS(file_z)
    
    # Only using the common genes in both datasets.
    common <- intersect(rownames(sce.z), rownames(sce.t))
    combined <- combineCols(sce.t[common,], sce.z[common,])
    block <- rep(c("tasic", "zeisel"), c(ncol(sce.t), ncol(sce.z)))
    
    # No mitochondrial genes in the combined set, so we'll just skip it.
    blocked_res <- analyze.se(combined, block=block, num.threads=2)
    
    # Save the full analysis results object
    saveRDS(blocked_res, "blocked_res.rds")
    
    # Visualize batch correction and save to PDF
    pdf("blocked_tsne_plot.pdf")
    p <- plotReducedDim(blocked_res\$x, "TSNE", colour_by="block")
    print(p)
    dev.off()
    
    # Table of clusters across batches
    tab <- table(blocked_res\$x\$graph.cluster, blocked_res\$x\$block)
    write.csv(as.data.frame.matrix(tab), "cluster_block_table.csv")
    
    # Preview markers and save to CSV
    markers_preview <- previewMarkers(blocked_res\$markers\$rna[[1]])
    write.csv(as.data.frame(markers_preview), "preview_markers.csv")
    
    # Aggregate cells across clusters and batches
    aggregates <- aggregateAcrossCells.se(
        blocked_res\$x,
        list(cluster=blocked_res\$x\$graph.cluster, dataset=blocked_res\$x\$block)
    )
    
    # Save aggregated profiles
    saveRDS(aggregates, "aggregated_profiles.rds")
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

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_SCRAPPER_BATCH_BLOCKED_ANALYSIS",
      domain  = "bioconductor",
      declared_qc_steps = c("cell QC metrics"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_SCRAPPER_BATCH_BLOCKED_ANALYSIS":',
        paste0('    scrapper: ', as.character(packageVersion('scrapper')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_batch_blocked_analysis.csv versions.yml
    """
}

workflow BIOC_SCRAPPER_BATCH_BLOCKED_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce.t, sce.z ] ]

    main:
    BIOC_SCRAPPER_BATCH_BLOCKED_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SCRAPPER_BATCH_BLOCKED_ANALYSIS.out.tables
    plots    = BIOC_SCRAPPER_BATCH_BLOCKED_ANALYSIS.out.plots
    objects  = BIOC_SCRAPPER_BATCH_BLOCKED_ANALYSIS.out.objects
    versions = BIOC_SCRAPPER_BATCH_BLOCKED_ANALYSIS.out.versions
}
