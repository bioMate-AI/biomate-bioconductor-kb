#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SpaNorm — svg_and_dimension_reduction
// Identify spatially variable genes (SVGs) and perform dimension reduction (PCA) on normalised spatial transcriptomics data.
// Input: Normalised SpatialExperiment object.
// Container: quay.io/biocontainers/bioconductor-spanorm:1.4.0--r45hdfd78af_0
// R packages: SpaNorm, SpatialExperiment, ggplot2, scater
// Bioconductor: 3.20 | R: 4.4
// Requires: SpaNorm, SpatialExperiment, ggplot2, scater
// Visualizations: UMAP plot
// QC: cell QC metrics
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Read the user-provided Normalised SpatialExperiment object
//  * 2. [Core Analysis] Identify Spatially Variable Genes (SVGs)
//  * 3. [Core Analysis] Extract top SVGs
//  * 4. [Core Analysis] Clean up gene names (replace hyphens with dots)
//  * 5. [Core Analysis] Perform PCA using SpaNormPCA
//  * 6. [Core Analysis] Run UMAP
//  * 7. [Core Analysis] Plot UMAP and save to PDF
//  * 8. [Core Analysis] Save outputs

nextflow.enable.dsl = 2

process BIOC_SPANORM_SVG_AND_DIMENSION_REDUCTION {
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
    .bm_deps <- c("SpaNorm", "SpatialExperiment", "ggplot2", "scater")
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
        library(SpaNorm)
        library(SpatialExperiment)
        library(scater)
        library(ggplot2)
        
        # --- Read the user-provided Normalised SpatialExperiment object ---
        input_file <- "normalised_spatial_experiment.rds"
        if (!file.exists(input_file)) {
          stop(paste("Error: Input file", input_file, "not found in the working directory."))
        }
        
        HumanDLPFC <- readRDS(input_file)
        
        # --- Identify Spatially Variable Genes (SVGs) ---
        HumanDLPFC = SpaNormSVG(HumanDLPFC)
        
        # --- Extract top SVGs ---
        svgs = topSVGs(HumanDLPFC, n = 10)
        
        # --- Clean up gene names (replace hyphens with dots) ---
        rownames(HumanDLPFC) = gsub("-", ".", rownames(HumanDLPFC))
        if (is.character(svgs)) {
          svgs = gsub("-", ".", svgs)
        } else {
          rownames(svgs) = gsub("-", ".", rownames(svgs))
        }
        
        # --- Perform PCA using SpaNormPCA ---
        HumanDLPFC = SpaNormPCA(HumanDLPFC, ncomponents = 50, svg.fdr = 0.2, nsvgs = Inf)
        
        # --- Run UMAP ---
        HumanDLPFC = runUMAP(HumanDLPFC, n_neighbors = 20, min_dist = 0.3)
        
        # --- Plot UMAP and save to PDF ---
        pdf("umap_plot.pdf", width = 8, height = 6)
        p <- plotUMAP(HumanDLPFC)
        print(p)
        dev.off()
        
        # --- Save outputs ---
        write.csv(as.data.frame(svgs), "top_svgs.csv", row.names = TRUE)
        saveRDS(HumanDLPFC, "processed_spatial_experiment.rds")
        
        message("Pipeline completed successfully. Outputs saved: 'top_svgs.csv', 'processed_spatial_experiment.rds', and 'umap_plot.pdf'.")
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
      process = "BIOC_SPANORM_SVG_AND_DIMENSION_REDUCTION",
      domain  = "bioconductor",
      declared_qc_steps = c("cell QC metrics"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_SPANORM_SVG_AND_DIMENSION_REDUCTION":',
        paste0('    SpaNorm: ', as.character(packageVersion('SpaNorm')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_svg_and_dimension_reduction.csv versions.yml
    """
}

workflow BIOC_SPANORM_SVG_AND_DIMENSION_REDUCTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Normalised SpatialExperiment object. ] ]

    main:
    BIOC_SPANORM_SVG_AND_DIMENSION_REDUCTION(ch_input)

    emit:
    tables   = BIOC_SPANORM_SVG_AND_DIMENSION_REDUCTION.out.tables
    plots    = BIOC_SPANORM_SVG_AND_DIMENSION_REDUCTION.out.plots
    objects  = BIOC_SPANORM_SVG_AND_DIMENSION_REDUCTION.out.objects
    versions = BIOC_SPANORM_SVG_AND_DIMENSION_REDUCTION.out.versions
}
