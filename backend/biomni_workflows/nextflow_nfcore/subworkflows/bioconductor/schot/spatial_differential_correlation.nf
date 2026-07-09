#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scHOT — spatial_differential_correlation
// Test for spatial differential correlation between pairs of genes across spatial coordinates.
// Input: spatial_sce.rds
// Container: quay.io/biocontainers/bioconductor-schot:1.22.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, ggplot2, matrixStats, scHOT, scater
// Visualizations: plot (ggplot/base)
// QC: cell QC metrics
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Build scHOT object from SingleCellExperiment using scHOT_buildFromSCE
//  * 2. [Core Analysis] Add gene pairs to testing scaffold using scHOT_addTestingScaffold
//  * 3. [Core Analysis] Run the wrapper function scHOT to perform weight matrix setup, global function calculation, permutation testing, and test statisti
//  * 4. [Core Analysis] Estimate p-values using scHOT_estimatePvalues
//  * 5. [Visualization & Output] Plot results using plotOrderedExpression and plotHigherOrderSequence

nextflow.enable.dsl = 2

process BIOC_SCHOT_SPATIAL_DIFFERENTIAL_CORRELATION {
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
    .bm_deps <- c("scHOT", "ggplot2", "matrixStats", "scater", "SummarizedExperiment")
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
            
    library(SummarizedExperiment)
    
    library(scHOT)
    library(ggplot2)
    library(matrixStats)
    library(scater)
    
    # Read user input
    sce_MOB_subset <- readRDS("spatial_sce.rds")
    
    # Construct pairs scaffold
    pairs <- t(combn(rownames(sce_MOB_subset), 2))
    rownames(pairs) <- apply(pairs, 1, paste0, collapse = "_")
    
    set.seed(2020)
    pairs <- pairs[sample(nrow(pairs), min(20, nrow(pairs))), , drop = FALSE]
    
    # 1. Build scHOT object
    scHOT_spatial <- scHOT_buildFromSCE(sce_MOB_subset,
                                        assayName = "logcounts",
                                        positionType = "spatial",
                                        positionColData = c("x", "y"))
    
    # 2. Add testing scaffold
    scHOT_spatial <- scHOT_addTestingScaffold(scHOT_spatial, pairs)
    
    # 3. Run scHOT wrapper
    scHOT_spatial <- scHOT(scHOT_spatial,
                           testingScaffold = pairs,
                           positionType = "spatial",
                           positionColData = c("x", "y"),
                           nrow.out = NULL,
                           higherOrderFunction = weightedSpearman,
                           higherOrderFunctionType = "weighted",
                           numberPermutations = 50,
                           numberScaffold = 10,
                           higherOrderSummaryFunction = sd,
                           parallel = FALSE,
                           verbose = FALSE,
                           span = 0.05)
    
    # 4. Estimate p-values
    scHOT_spatial <- scHOT_estimatePvalues(scHOT_spatial,
                                           nperm_estimate = 100,
                                           maxDist = 0.1)
    
    # Prepare for plotting (add -x coordinate)
    colData(scHOT_spatial)[, "-x"] <- -colData(scHOT_spatial)[, "x"]
    
    # 5. Plot results and save to PDF
    pdf("scHOT_spatial_plots.pdf", width = 10, height = 8)
    
    plot_pair_name <- rownames(pairs)[1]
    plot_genes <- as.character(pairs[1, ])
    
    p1 <- plotOrderedExpression(scHOT_spatial, plot_genes,
                                positionColData = c("-x", "y"),
                                assayName = "expression")
    print(p1)
    
    p2 <- plotHigherOrderSequence(scHOT_spatial, plot_pair_name,
                                  positionColData = c("-x", "y"))
    print(p2)
    
    dev.off()
    
    # Save outputs
    saveRDS(scHOT_spatial, "scHOT_spatial_output.rds")
    
    # Extract and save the results table
    results_df <- as.data.frame(slot(scHOT_spatial, "scHOT_output"))
    
    # Flatten or remove list columns for standard CSV compatibility
    results_df\$higherOrderSequence <- sapply(results_df\$higherOrderSequence, function(x) paste(x, collapse = ";"))
    results_df\$permutations <- sapply(results_df\$permutations, function(x) paste(x, collapse = ";"))
    
    write.csv(results_df, "scHOT_spatial_results.csv", row.names = TRUE)
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

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_SCHOT_SPATIAL_DIFFERENTIAL_CORRELATION",
      domain  = "bioconductor",
      declared_qc_steps = c("cell QC metrics"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_SCHOT_SPATIAL_DIFFERENTIAL_CORRELATION":',
        paste0('    scHOT: ', as.character(packageVersion('scHOT')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spatial_differential_correlation.csv versions.yml
    """
}

workflow BIOC_SCHOT_SPATIAL_DIFFERENTIAL_CORRELATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ spatial_sce.rds ] ]

    main:
    BIOC_SCHOT_SPATIAL_DIFFERENTIAL_CORRELATION(ch_input)

    emit:
    tables   = BIOC_SCHOT_SPATIAL_DIFFERENTIAL_CORRELATION.out.tables
    plots    = BIOC_SCHOT_SPATIAL_DIFFERENTIAL_CORRELATION.out.plots
    objects  = BIOC_SCHOT_SPATIAL_DIFFERENTIAL_CORRELATION.out.objects
    versions = BIOC_SCHOT_SPATIAL_DIFFERENTIAL_CORRELATION.out.versions
}
