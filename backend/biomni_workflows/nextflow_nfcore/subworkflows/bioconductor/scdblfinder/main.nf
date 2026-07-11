#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scDblFinder — sc_dbl_finder
// Run the main scDblFinder workflow on a SingleCellExperiment object to score and classify doublets.
// Input: sce.rds
// Container: quay.io/biocontainers/bioconductor-scdblfinder:1.24.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, SingleCellExperiment, scDblFinder
// Visualizations: plot (ggplot/base)
// QC: doublet detection QC
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Set random seed for reproducibility
//  * 2. [Core Analysis] Run scDblFinder with optional doublet rate (dbr), cluster information (clusters), or sample splitting (samples)
//  * 3. [Core Analysis] Inspect results in colData (scDblFinder.score and scDblFinder.class)

nextflow.enable.dsl = 2

process BIOC_SCDBLFINDER_SC_DBL_FINDER {
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
    .bm_deps <- c("SingleCellExperiment", "scDblFinder", "BiocParallel")
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
            
    # 1. Set random seed for reproducibility
    set.seed(123)
    
    # Load required libraries
    suppressPackageStartupMessages(library(SingleCellExperiment))
    suppressPackageStartupMessages(library(scDblFinder))
    suppressPackageStartupMessages(library(BiocParallel))
    
    # Load user input
    if (!file.exists("sce.rds")) {
      stop("Required input file 'sce.rds' not found in the working directory.")
    }
    sce <- readRDS("sce.rds")
    
    # Ensure counts assay is present and correctly named
    if (!"counts" %in% assayNames(sce)) {
      if (length(assays(sce)) > 0) {
        assayNames(sce)[1] <- "counts"
      } else {
        stop("The input SingleCellExperiment object must contain at least one assay (counts).")
      }
    }
    
    # 2. Run scDblFinder with cluster information and sample splitting
    bp <- SnowParam(3, RNGseed=1234)
    
    scDblFinder_args <- list(sce = sce, BPPARAM = bp)
    
    if ("cluster" %in% colnames(colData(sce))) {
      scDblFinder_args\$clusters <- "cluster"
    }
    
    if ("sample_id" %in% colnames(colData(sce))) {
      scDblFinder_args\$samples <- "sample_id"
    }
    
    sce <- do.call(scDblFinder, scDblFinder_args)
    
    # 3. Inspect results in colData (scDblFinder.score and scDblFinder.class)
    cat("Doublet detection summary:\n")
    print(table(Class = sce\$scDblFinder.class))
    
    # Write named output files for the meaningful results
    # Save the updated SingleCellExperiment object
    saveRDS(sce, "sce_scDblFinder.rds")
    
    # Save a CSV table of the doublet scores and classifications
    results_df <- data.frame(
      Cell = colnames(sce),
      scDblFinder.score = sce\$scDblFinder.score,
      scDblFinder.class = sce\$scDblFinder.class,
      stringsAsFactors = FALSE
    )
    write.csv(results_df, "scDblFinder_results.csv", row.names = FALSE)
    
    # Save a PDF plot of the doublet score distribution
    pdf("scDblFinder_score_histogram.pdf", width = 6, height = 4)
    hist(sce\$scDblFinder.score, 
         breaks = 50, 
         main = "Distribution of scDblFinder Scores", 
         xlab = "Doublet Score", 
         col = "skyblue", 
         border = "white")
    dev.off()
    
    cat("Pipeline completed successfully. Outputs saved: scDblFinder_results.csv, sce_scDblFinder.rds, scDblFinder_score_histogram.pdf\n")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # doublet detection — SCE/Seurat with doublet column; pass: rate ≤ 10%.
    .dbl_rate <- NA_real_
    for (.dbl_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
      .dbl_obj <- tryCatch(readRDS(.dbl_rds), error = function(e) NULL)
      .dbl_calls <- NULL
      if (!is.null(.dbl_obj)) {
        if (inherits(.dbl_obj, "SingleCellExperiment")) {
          .dbl_cd <- tryCatch(colData(.dbl_obj), error = function(e) NULL)
          if (!is.null(.dbl_cd)) {
            .dbl_col <- intersect(c("doublet_class","scDblFinder.class","DoubletFinder","is_doublet"), colnames(.dbl_cd))
            if (length(.dbl_col) > 0) .dbl_calls <- as.character(.dbl_cd[[.dbl_col[1]]])
          }
        } else if (inherits(.dbl_obj, "Seurat")) {
          .dbl_md <- tryCatch(.dbl_obj@meta.data, error = function(e) NULL)
          if (!is.null(.dbl_md)) {
            .dbl_col <- intersect(c("DoubletFinder","scDblFinder.class","doublet_class","is_doublet"), colnames(.dbl_md))
            if (length(.dbl_col) > 0) .dbl_calls <- as.character(.dbl_md[[.dbl_col[1]]])
          }
        }
      }
      if (!is.null(.dbl_calls) && length(.dbl_calls) > 0) {
        .dbl_rate <- round(mean(grepl("doublet|TRUE|1", .dbl_calls, ignore.case = TRUE), na.rm = TRUE), 4); break
      }
    }
    .gates_by_label[["doublet detection QC"]] <- list(
      gate_row = "bioc_doublet_detection_qc",
      metric_name = "doublet_rate",
      metric_value = .dbl_rate,
      passes = isTRUE(is.finite(.dbl_rate) && .dbl_rate <= 0.10),
      status = if (is.finite(.dbl_rate)) "computed (SCE colData / Seurat meta.data doublet col)"
               else "not_computed (no SCE/Seurat with doublet column present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_SCDBLFINDER_SC_DBL_FINDER",
      domain  = "bioconductor",
      declared_qc_steps = c("doublet detection QC"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_SCDBLFINDER_SC_DBL_FINDER":',
        paste0('    scDblFinder: ', as.character(packageVersion('scDblFinder')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sc_dbl_finder.csv versions.yml
    """
}

workflow BIOC_SCDBLFINDER_SC_DBL_FINDER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce.rds ] ]

    main:
    BIOC_SCDBLFINDER_SC_DBL_FINDER(ch_input)

    emit:
    tables   = BIOC_SCDBLFINDER_SC_DBL_FINDER.out.tables
    plots    = BIOC_SCDBLFINDER_SC_DBL_FINDER.out.plots
    objects  = BIOC_SCDBLFINDER_SC_DBL_FINDER.out.objects
    versions = BIOC_SCDBLFINDER_SC_DBL_FINDER.out.versions
}
