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
    .bm_deps <- c("scHOT", "ggplot2", "matrixStats", "scater")
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
