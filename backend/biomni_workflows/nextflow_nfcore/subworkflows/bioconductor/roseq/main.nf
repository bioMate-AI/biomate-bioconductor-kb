#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ROSeq — roseq_de_analysis
// Perform rank-based differential expression analysis on single-cell RNA-Seq data.
// Input: count_matrix.csv, cell_metadata.csv
// Container: quay.io/biocontainers/bioconductor-roseq:1.22.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ROSeq, edgeR, limma
// QC: voom mean-variance modelling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load required libraries
//  * 2. [Core Analysis] Filter cells and genes based on expression thresholds
//  * 3. [Core Analysis] Perform TMM normalization using ROSeq::TMMnormalization
//  * 4. [Core Analysis] Apply voom transformation using limma::voom
//  * 5. [Core Analysis] Run differential expression analysis using ROSeq

nextflow.enable.dsl = 2

process BIOC_ROSEQ_ROSEQ_DE_ANALYSIS {
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
    .bm_deps <- c("ROSeq", "edgeR", "limma")
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
    library(ROSeq)
    library(edgeR)
    library(limma)
    
    # Read user input files
    # count_matrix.csv: raw read count matrix with genes in rows and cells in columns
    count_matrix <- read.csv("count_matrix.csv", row.names = 1, check.names = FALSE)
    
    # cell_metadata.csv: cell-annotation/condition mapping cells to contrasting groups
    cell_metadata <- read.csv("cell_metadata.csv", row.names = 1, check.names = FALSE)
    
    # Align cells between count matrix and metadata
    common_cells <- intersect(colnames(count_matrix), rownames(cell_metadata))
    if (length(common_cells) == 0) {
      stop("No common cells found between count_matrix.csv columns and cell_metadata.csv row names.")
    }
    count_matrix <- count_matrix[, common_cells, drop = FALSE]
    cell_metadata <- cell_metadata[common_cells, , drop = FALSE]
    
    # Determine the condition/group column
    group_col <- "group"
    if (!group_col %in% colnames(cell_metadata)) {
      if ("condition" %in% colnames(cell_metadata)) {
        group_col <- "condition"
      } else {
        group_col <- colnames(cell_metadata)[1]
      }
    }
    
    # Construct the samples list
    samples <- list()
    samples\$count <- as.matrix(count_matrix)
    samples\$group <- cell_metadata[[group_col]]
    
    # Preprocessing: Cells and genes filtering
    gene_names <- rownames(samples\$count)
    samples\$count <- apply(samples\$count, 2, function(x) as.numeric(x))
    rownames(samples\$count) <- gene_names
    
    # Filter cells based on expression thresholds (with fallback for small datasets)
    cell_keep <- colSums(samples\$count > 0) > 2000
    if (sum(cell_keep) < 2) {
      # Fallback if too few cells pass the 2000 genes threshold
      cell_keep <- rep(TRUE, ncol(samples\$count))
    }
    samples\$count <- samples\$count[, cell_keep, drop = FALSE]
    samples\$group <- samples\$group[cell_keep]
    
    # Filter genes based on expression thresholds (with fallback)
    gkeep <- apply(samples\$count, 1, function(x) sum(x > 2) >= 3)
    if (sum(gkeep) < 2) {
      gkeep <- rep(TRUE, nrow(samples\$count))
    }
    samples\$count <- samples\$count[gkeep, , drop = FALSE]
    
    # Perform TMM normalization and voom transformation
    samples\$count <- limma::voom(ROSeq::TMMnormalization(samples\$count))
    
    # Run ROSeq differential expression analysis
    output <- ROSeq(countData = samples\$count\$E, condition = samples\$group, numCores = 1)
    
    # Write outputs
    write.csv(output, "roseq_de_results.csv", row.names = TRUE)
    saveRDS(output, "roseq_de_results.rds")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # voom — limma EList\$weights present, range > 0 (Law 2014 GB).
    .voom_w_range <- NA_real_
    for (.voom_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .voom_obj <- tryCatch(readRDS(.voom_rds), error = function(e) NULL)
      if (!is.null(.voom_obj) && inherits(.voom_obj, "EList")) {
        .voom_w <- tryCatch(.voom_obj\$weights, error = function(e) NULL)
        if (!is.null(.voom_w) && length(.voom_w) > 0) {
          .voom_w_range <- round(diff(range(.voom_w, na.rm = TRUE)), 4); break
        }
      }
    }
    .gates_by_label[["voom mean-variance modelling"]] <- list(
      gate_row = "bioc_voom_mean_variance",
      metric_name = "voom_weight_range",
      metric_value = .voom_w_range,
      passes = isTRUE(is.finite(.voom_w_range) && .voom_w_range > 0),
      status = if (is.finite(.voom_w_range)) "computed (EList\$weights range)"
               else "not_computed (no limma EList .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_ROSEQ_ROSEQ_DE_ANALYSIS",
      domain  = "bioconductor",
      declared_qc_steps = c("voom mean-variance modelling"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_ROSEQ_ROSEQ_DE_ANALYSIS":',
        paste0('    ROSeq: ', as.character(packageVersion('ROSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_roseq_de_analysis.csv versions.yml
    """
}

workflow BIOC_ROSEQ_ROSEQ_DE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ count_matrix.csv, cell_metadata.csv ] ]

    main:
    BIOC_ROSEQ_ROSEQ_DE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_ROSEQ_ROSEQ_DE_ANALYSIS.out.tables
    plots    = BIOC_ROSEQ_ROSEQ_DE_ANALYSIS.out.plots
    objects  = BIOC_ROSEQ_ROSEQ_DE_ANALYSIS.out.objects
    versions = BIOC_ROSEQ_ROSEQ_DE_ANALYSIS.out.versions
}
