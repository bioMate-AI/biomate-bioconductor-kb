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

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
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
