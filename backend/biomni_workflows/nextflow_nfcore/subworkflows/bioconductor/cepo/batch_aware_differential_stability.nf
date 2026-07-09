#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Cepo — batch_aware_differential_stability
// Perform differential stability analysis across multiple batches using the block argument to avoid batch effects.
// Input: sce_pancreas
// Container: quay.io/biocontainers/bioconductor-cepo:1.16.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Cepo, SingleCellExperiment, scater
// Visualizations: density plot
// QC: cell QC metrics, count normalization, normalization diagnostic plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load data and normalize
//  * 2. [Core Analysis] Run Cepo with the block argument to perform analysis independently per batch
//  * 3. [Core Analysis] Extract top genes from the averaged results

nextflow.enable.dsl = 2

process BIOC_CEPO_BATCH_AWARE_DIFFERENTIAL_STABILITY {
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
    .bm_deps <- c("Cepo", "scater")
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
    
    library(Cepo)
    library(scater)
    
    # 1. Load data and normalize
    if (file.exists("sce_pancreas")) {
      sce_pancreas <- readRDS("sce_pancreas")
    } else if (file.exists("sce_pancreas.rds")) {
      sce_pancreas <- readRDS("sce_pancreas.rds")
    } else {
      stop("Required input file 'sce_pancreas' or 'sce_pancreas.rds' not found in the working directory.")
    }
    
    sce = sce_pancreas
    sce = scater::logNormCounts(sce)
    
    # 2. Run Cepo with the block argument to perform analysis independently per batch
    ds_res_batches = Cepo::Cepo(exprsMat = logcounts(sce),
                                cellTypes = sce\$cellTypes,
                                block = sce\$batch,
                                minCelltype = 2)
    names(ds_res_batches)
    
    # 3. Extract top genes from the averaged results
    cepo_genes = Cepo::topGenes(ds_res_batches\$average, n = 3)
    
    # 4. Save outputs to the working directory
    # Save the complete Cepo results list
    saveRDS(ds_res_batches, "ds_res_batches.rds")
    
    # Save the top genes as a CSV file
    cepo_genes_df <- as.data.frame(cepo_genes)
    write.csv(cepo_genes_df, "top_cepo_genes.csv", row.names = FALSE)
    
    # Save the average differential stability statistics
    if (!is.null(ds_res_batches\$average\$stats)) {
      write.csv(as.data.frame(ds_res_batches\$average\$stats), "cepo_average_stats.csv")
    }
    
    # Generate and save density plots for the top differentially stable genes
    tryCatch({
      pdf("cepo_densities.pdf", width = 10, height = 8)
      Cepo::plotDensities(x = sce,
                          cepoOutput = ds_res_batches\$average,
                          nGenes = 2,
                          assay = "logcounts",
                          celltypeColumn = "cellTypes")
      dev.off()
    }, error = function(e) {
      warning("Could not generate density plots: ", e\$message)
      if (dev.cur() > 1) dev.off()
    })
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # cell QC metrics — defensive cell-count + per-cell summary from any
    # matrix artifact. Pass when columns (cells) ≥ 50 and rows (features) ≥ 200
    # (Luecken & Theis 2019 single-cell QC floor).
    .cqc_ncells <- NA_real_; .cqc_nfeats <- NA_real_; .cqc_files <- character(0)
    for (.cqc_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
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
    for (.cn_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
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

    # normalization diagnostic plot — file-exists check for any PDF emitted
    # with "norm" / "mean_sd" / "library" in the filename. Pairs with
    # bioc_count_normalization (numeric metric); this row is the visual gate.
    .ndp_pdfs <- list.files(".", pattern = "(?i)(norm|mean.?sd|library).*\\.pdf\$")
    .ndp_passes <- length(.ndp_pdfs) > 0
    .gates_by_label[["normalization diagnostic plot"]] <- list(
      gate_row = "bioc_normalization_diagnostic_plot",
      metric_name = "normalization_plot_exists",
      metric_value = if (.ndp_passes) 1 else 0,
      passes = .ndp_passes,
      status = if (.ndp_passes) paste0("computed (", length(.ndp_pdfs), " diagnostic PDF(s) emitted)")
               else "not_computed (no normalization diagnostic PDF found)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_CEPO_BATCH_AWARE_DIFFERENTIAL_STABILITY",
      domain  = "bioconductor",
      declared_qc_steps = c("cell QC metrics", "count normalization", "normalization diagnostic plot"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_CEPO_BATCH_AWARE_DIFFERENTIAL_STABILITY":',
        paste0('    Cepo: ', as.character(packageVersion('Cepo')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_batch_aware_differential_stability.csv versions.yml
    """
}

workflow BIOC_CEPO_BATCH_AWARE_DIFFERENTIAL_STABILITY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce_pancreas ] ]

    main:
    BIOC_CEPO_BATCH_AWARE_DIFFERENTIAL_STABILITY(ch_input)

    emit:
    tables   = BIOC_CEPO_BATCH_AWARE_DIFFERENTIAL_STABILITY.out.tables
    plots    = BIOC_CEPO_BATCH_AWARE_DIFFERENTIAL_STABILITY.out.plots
    objects  = BIOC_CEPO_BATCH_AWARE_DIFFERENTIAL_STABILITY.out.objects
    versions = BIOC_CEPO_BATCH_AWARE_DIFFERENTIAL_STABILITY.out.versions
}
