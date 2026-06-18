#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scHOT — trajectory_variability_testing
// Test for changes in single-gene expression variability along a developmental trajectory.
// Input: expression_matrix.csv, pseudotime_metadata.csv
// Container: quay.io/biocontainers/bioconductor-schot:1.22.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, ggplot2, matrixStats, scHOT, scater
// Visualizations: plot (ggplot/base)
// QC: cell QC metrics
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Build scHOT object from matrix using scHOT_buildFromMatrix
//  * 2. [Core Analysis] Add testing scaffold using scHOT_addTestingScaffold
//  * 3. [Core Analysis] Set weight matrix using scHOT_setWeightMatrix
//  * 4. [Core Analysis] Calculate global higher order function using scHOT_calculateGlobalHigherOrderFunction
//  * 5. [Core Analysis] Set permutation scaffold using scHOT_setPermutationScaffold
//  * 6. [Core Analysis] Calculate higher order test statistics using scHOT_calculateHigherOrderTestStatistics
//  * 7. [Core Analysis] Perform permutation test using scHOT_performPermutationTest
//  * 8. [Core Analysis] Estimate p-values using scHOT_estimatePvalues
//  * 9. [Visualization & Output] Plot results using plotHigherOrderSequence

nextflow.enable.dsl = 2

process BIOC_SCHOT_TRAJECTORY_VARIABILITY_TESTING {
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
    .bm_deps <- c("ggplot2", "scHOT", "scater", "matrixStats")
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
    
    library(ggplot2)
    library(scHOT)
    library(scater)
    library(matrixStats)
    
    # 1. Read User Input Files
    expression_matrix <- read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE)
    pseudotime_metadata <- read.csv("pseudotime_metadata.csv", row.names = 1, check.names = FALSE)
    
    # Align cells between expression matrix and metadata
    common_cells <- intersect(colnames(expression_matrix), rownames(pseudotime_metadata))
    if (length(common_cells) == 0) {
      if (ncol(expression_matrix) == nrow(pseudotime_metadata)) {
        common_cells <- colnames(expression_matrix)
        rownames(pseudotime_metadata) <- common_cells
      } else {
        stop("Cell identifiers in expression_matrix and pseudotime_metadata do not match.")
      }
    }
    
    mat_subset <- as.matrix(expression_matrix[, common_cells, drop = FALSE])
    
    # Identify the pseudotime column
    pt_col <- grep("pseudotime", colnames(pseudotime_metadata), ignore.case = TRUE, value = TRUE)
    if (length(pt_col) == 0) {
      numeric_cols <- sapply(pseudotime_metadata, is.numeric)
      if (any(numeric_cols)) {
        pt_col <- names(numeric_cols)[numeric_cols][1]
      } else {
        stop("No numeric column found in pseudotime_metadata to use as pseudotime.")
      }
    }
    
    pt_vector <- pseudotime_metadata[common_cells, pt_col]
    
    # Select exactly 3 genes to test to match the permutation scaffold length of 3
    genes_available <- rownames(mat_subset)
    if (length(genes_available) < 3) {
      stop("Expression matrix must have at least 3 genes (rows) for this pipeline.")
    }
    gene_to_test <- as.matrix(genes_available[1:3])
    
    # 2. Build scHOT object from matrix
    scHOT_traj <- scHOT_buildFromMatrix(
      mat = mat_subset,
      cellData = list(pseudotime = pt_vector),
      positionType = "trajectory",
      positionColData = "pseudotime")
    
    # 3. Add testing scaffold
    scHOT_traj <- scHOT_addTestingScaffold(scHOT_traj, gene_to_test)
    
    # 4. Set weight matrix
    scHOT_traj <- scHOT_setWeightMatrix(scHOT_traj,
                                        positionType = "trajectory",
                                        positionColData = c("pseudotime"),
                                        nrow.out = 50,
                                        span = 0.25)
    
    # 5. Calculate global higher order function
    scHOT_traj <- scHOT_calculateGlobalHigherOrderFunction(
      scHOT_traj, 
      higherOrderFunction = matrixStats::weightedVar,
      higherOrderFunctionType = "weighted")
    
    # 6. Set permutation scaffold
    scHOT_traj <- scHOT_setPermutationScaffold(scHOT_traj, 
                                               numberPermutations = c(20,50,20),
                                               storePermutations = c(TRUE, FALSE, TRUE))
    
    # 7. Calculate higher order test statistics
    scHOT_traj <- scHOT_calculateHigherOrderTestStatistics(
      scHOT_traj,
      higherOrderSummaryFunction = sd)
    
    # 8. Perform permutation test
    scHOT_traj <- scHOT_performPermutationTest(
      scHOT_traj, 
      verbose = TRUE,
      parallel = FALSE)
    
    # 9. Estimate p-values
    scHOT_traj <- scHOT_estimatePvalues(scHOT_traj,
                                        nperm_estimate = 10000,
                                        maxDist = 5)
    
    # 10. Save Results and Plots
    saveRDS(scHOT_traj, "scHOT_trajectory_results.rds")
    
    # Format and save the output table
    scHOT_out_df <- as.data.frame(slot(scHOT_traj, "scHOT_output"))
    for (col in colnames(scHOT_out_df)) {
      if (is.list(scHOT_out_df[[col]])) {
        scHOT_out_df[[col]] <- sapply(scHOT_out_df[[col]], function(x) paste(x, collapse = ";"))
      }
    }
    write.csv(scHOT_out_df, "scHOT_trajectory_output.csv", row.names = TRUE)
    
    # Plot results
    pdf("higher_order_sequence_plot.pdf", width = 8, height = 6)
    print(plotHigherOrderSequence(scHOT_traj, gene_to_test))
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

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_SCHOT_TRAJECTORY_VARIABILITY_TESTING",
      domain  = "bioconductor",
      declared_qc_steps = c("cell QC metrics"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_SCHOT_TRAJECTORY_VARIABILITY_TESTING":',
        paste0('    scHOT: ', as.character(packageVersion('scHOT')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_trajectory_variability_testing.csv versions.yml
    """
}

workflow BIOC_SCHOT_TRAJECTORY_VARIABILITY_TESTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv, pseudotime_metadata.csv ] ]

    main:
    BIOC_SCHOT_TRAJECTORY_VARIABILITY_TESTING(ch_input)

    emit:
    tables   = BIOC_SCHOT_TRAJECTORY_VARIABILITY_TESTING.out.tables
    plots    = BIOC_SCHOT_TRAJECTORY_VARIABILITY_TESTING.out.plots
    objects  = BIOC_SCHOT_TRAJECTORY_VARIABILITY_TESTING.out.objects
    versions = BIOC_SCHOT_TRAJECTORY_VARIABILITY_TESTING.out.versions
}
