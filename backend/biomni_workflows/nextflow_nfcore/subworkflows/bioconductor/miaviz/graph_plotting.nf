#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: miaViz — graph_plotting
// Plot sample or feature graphs integrated with metadata from a SummarizedExperiment.
// Input: col_graph, GlobalPatterns
// Container: quay.io/biocontainers/bioconductor-miaviz:1.18.0--r45hdfd78af_0
// R packages: ggplot2, mia, miaViz, scater
// Bioconductor: 3.20 | R: 4.4
// Requires: ggplot2, mia, miaViz, scater
// Visualizations: plot (ggplot/base)
// QC: cell QC metrics
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load graph data
//  * 2. [Visualization & Output] Plot column graph mapping sample metadata to node colors and edge weights
//  * 3. [Visualization & Output] Store graph in metadata slot and plot

nextflow.enable.dsl = 2

process BIOC_MIAVIZ_GRAPH_PLOTTING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metagenomics:3.20-deps"

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
    .bm_deps <- c("ggplot2", "mia", "miaViz", "scater")
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
    library(miaViz)
    library(scater)
    library(mia)
    library(ggplot2)
    
    # 1. Load graph data and TreeSummarizedExperiment object from user input files
    col_graph <- readRDS("col_graph")
    GlobalPatterns <- readRDS("GlobalPatterns")
    
    # Ensure the "Genus" alternative experiment exists in GlobalPatterns
    if (!"Genus" %in% altExpNames(GlobalPatterns)) {
        altExp(GlobalPatterns, "Genus") <- agglomerateByRank(GlobalPatterns, "Genus")
    }
    
    # 2. Plot column graph mapping sample metadata to node colors and edge weights
    plot1 <- plotColGraph(
        col_graph,
        altExp(GlobalPatterns,"Genus"),
        colour.by = "SampleType",
        edge.colour.by = "weight",
        edge.width.by = "weight",
        show.label = TRUE)
    
    # Save the first plot
    ggsave("col_graph_plot_direct.pdf", plot = plot1, width = 10, height = 8)
    
    # 3. Store graph in metadata slot and plot
    metadata(altExp(GlobalPatterns,"Genus"))\$graph <- col_graph
    
    plot2 <- plotColGraph(
        altExp(GlobalPatterns,"Genus"),
        name = "graph",
        colour.by = "SampleType",
        edge.colour.by = "weight",
        edge.width.by = "weight",
        show.label = TRUE)
    
    # Save the second plot
    ggsave("col_graph_plot_metadata.pdf", plot = plot2, width = 10, height = 8)
    
    # Save the updated TreeSummarizedExperiment object with the graph in metadata
    saveRDS(GlobalPatterns, "GlobalPatterns_with_graph.rds")
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
      process = "BIOC_MIAVIZ_GRAPH_PLOTTING",
      domain  = "bioconductor",
      declared_qc_steps = c("cell QC metrics"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_MIAVIZ_GRAPH_PLOTTING":',
        paste0('    miaViz: ', as.character(packageVersion('miaViz')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_graph_plotting.csv versions.yml
    """
}

workflow BIOC_MIAVIZ_GRAPH_PLOTTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ col_graph, GlobalPatterns ] ]

    main:
    BIOC_MIAVIZ_GRAPH_PLOTTING(ch_input)

    emit:
    tables   = BIOC_MIAVIZ_GRAPH_PLOTTING.out.tables
    plots    = BIOC_MIAVIZ_GRAPH_PLOTTING.out.plots
    objects  = BIOC_MIAVIZ_GRAPH_PLOTTING.out.objects
    versions = BIOC_MIAVIZ_GRAPH_PLOTTING.out.versions
}
