#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: edgeR — fold_change_threshold_testing
// Test for differential expression relative to a specific fold-change threshold using a rigorous statistical test.
// Input: y
// Container: quay.io/biocontainers/bioconductor-edger:4.8.2--r45h01b2380_0
// R packages: edgeR
// Bioconductor: 3.20 | R: 4.4
// Requires: edgeR
// Visualizations: mean-difference plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define design matrix
//  * 2. [Core Analysis] Fit QL GLM model
//  * 3. [Core Analysis] Perform thresholded hypothesis testing
//  * 4. [Core Analysis] Extract top tags

nextflow.enable.dsl = 2

process BIOC_EDGER_FOLD_CHANGE_THRESHOLD_TESTING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("edgeR")
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
    library(edgeR)
    
    # 1. Read user input
    # The pipeline reads the DGEList object 'y.rds' from the working directory
    y <- readRDS("y.rds")
    
    # 2. Define design matrix
    # We construct the design matrix using the group variable in y\$samples.
    # If group is not defined, we create a default two-group factor.
    if (is.null(y\$samples\$group)) {
      y\$samples\$group <- factor(rep(c("Control", "Treatment"), length.out = ncol(y)))
    }
    design <- model.matrix(~ y\$samples\$group)
    
    # 3. Fit QL GLM model
    fit <- glmQLFit(y, design)
    
    # 4. Perform thresholded hypothesis testing
    tr <- glmTreat(fit, coef=2, lfc=1)
    
    # 5. Extract top tags
    # Print the default top tags to standard output
    topTags(tr)
    
    # 6. Write output files
    # Save the complete table of results to a CSV file
    all_tags <- topTags(tr, n = Inf)
    write.csv(as.data.frame(all_tags), "fold_change_threshold_testing_results.csv", row.names = TRUE)
    
    # Save the fitted model and testing objects as RDS files
    saveRDS(fit, "glmQLFit_object.rds")
    saveRDS(tr, "glmTreat_object.rds")
    
    # Generate a Mean-Difference (MD) plot to visualize the threshold testing results
    pdf("md_plot_threshold_testing.pdf")
    plotMD(tr)
    abline(h = c(-1, 1), col = "red", lty = 2)
    dev.off()

    writeLines(c(
        '"BIOC_EDGER_FOLD_CHANGE_THRESHOLD_TESTING":',
        paste0('    edgeR: ', as.character(packageVersion('edgeR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fold_change_threshold_testing.csv versions.yml
    """
}

workflow BIOC_EDGER_FOLD_CHANGE_THRESHOLD_TESTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ y ] ]

    main:
    BIOC_EDGER_FOLD_CHANGE_THRESHOLD_TESTING(ch_input)

    emit:
    tables   = BIOC_EDGER_FOLD_CHANGE_THRESHOLD_TESTING.out.tables
    plots    = BIOC_EDGER_FOLD_CHANGE_THRESHOLD_TESTING.out.plots
    objects  = BIOC_EDGER_FOLD_CHANGE_THRESHOLD_TESTING.out.objects
    versions = BIOC_EDGER_FOLD_CHANGE_THRESHOLD_TESTING.out.versions
}
