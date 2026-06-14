#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: dfp — step_by_step_fuzzy_pipeline
// Run the complete step-by-step fuzzy pattern discretization and discrimination pipeline starting from raw CSV files.
// Input: exprsData.csv, pData.csv
// Container: quay.io/biocontainers/bioconductor-dfp:1.68.0--r45hdfd78af_0
// R packages: DFP
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_DFP_STEP_BY_STEP_FUZZY_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-dfp:1.68.0--r45hdfd78af_0"

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
    .bm_deps <- c("DFP")
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
    
    # Load the required Bioconductor library
    library(DFP)
    
    # Define input file paths in the working directory
    fileExprs <- "exprsData.csv"
    filePhenodata <- "pData.csv"
    
    # Verify that the required input files exist
    if (!file.exists(fileExprs)) {
      stop(paste("Required input file missing:", fileExprs))
    }
    if (!file.exists(filePhenodata)) {
      stop(paste("Required input file missing:", filePhenodata))
    }
    
    # Read CSV files into an ExpressionSet
    rmadataset <- readCSV(fileExprs, filePhenodata)
    
    # Define pipeline parameters
    skipFactor <- 3
    zeta <- 0.5
    piVal <- 0.9
    overlapping <- 2
    
    # --- Calculate Membership Functions ---
    mfs <- calculateMembershipFunctions(rmadataset, skipFactor)
    saveRDS(mfs, "membership_functions.rds")
    
    # Plot Membership Functions (wrapped in tryCatch for robustness to feature names)
    tryCatch({
      pdf("membership_functions_plot.pdf", width = 8, height = 6)
      plotMembershipFunctions(rmadataset, mfs, featureNames(rmadataset)[1:2])
      dev.off()
    }, error = function(e) {
      warning("Could not plot membership functions: ", e\$message)
      if (dev.cur() > 1) dev.off()
    })
    
    # --- Discretize Expression Values ---
    dvs <- discretizeExpressionValues(rmadataset, mfs, zeta, overlapping)
    write.csv(dvs, "discretized_expression_values.csv", row.names = TRUE)
    
    # Show Discrete Values (wrapped in tryCatch for robustness to specific class labels)
    tryCatch({
      dvs_subset <- showDiscreteValues(dvs, featureNames(rmadataset)[1:10], c("healthy", "AML-inv"))
      write.csv(dvs_subset, "discrete_values_subset.csv", row.names = TRUE)
    }, error = function(e) {
      warning("Could not show discrete values for 'healthy' and 'AML-inv': ", e\$message)
    })
    
    # --- Calculate Fuzzy Patterns ---
    fps <- calculateFuzzyPatterns(rmadataset, dvs, piVal, overlapping)
    write.csv(fps, "fuzzy_patterns.csv", row.names = TRUE)
    
    # Show Fuzzy Patterns (wrapped in tryCatch for robustness to specific class labels)
    tryCatch({
      fps_subset <- showFuzzyPatterns(fps, "healthy")[21:50]
      write.csv(as.data.frame(fps_subset), "healthy_fuzzy_patterns_subset.csv", row.names = TRUE)
    }, error = function(e) {
      warning("Could not show fuzzy patterns for 'healthy': ", e\$message)
    })
    
    # --- Calculate Discriminant Fuzzy Patterns ---
    dfps <- calculateDiscriminantFuzzyPattern(rmadataset, fps)
    write.csv(dfps, "discriminant_fuzzy_patterns.csv", row.names = TRUE)
    
    # Plot Discriminant Fuzzy Patterns
    tryCatch({
      pdf("discriminant_fuzzy_pattern_plot.pdf", width = 10, height = 8)
      plotDiscriminantFuzzyPattern(dfps, overlapping)
      dev.off()
    }, error = function(e) {
      warning("Could not plot discriminant fuzzy patterns: ", e\$message)
      if (dev.cur() > 1) dev.off()
    })
    
    cat("Pipeline completed. Outputs saved to the working directory.\n")

    writeLines(c(
        '"BIOC_DFP_STEP_BY_STEP_FUZZY_PIPELINE":',
        paste0('        dfp: ', as.character(packageVersion("dfp")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_step_by_step_fuzzy_pipeline.csv versions.yml
    """
}

workflow BIOC_DFP_STEP_BY_STEP_FUZZY_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ exprsData.csv, pData.csv ] ]

    main:
    BIOC_DFP_STEP_BY_STEP_FUZZY_PIPELINE(ch_input)

    emit:
    tables   = BIOC_DFP_STEP_BY_STEP_FUZZY_PIPELINE.out.tables
    plots    = BIOC_DFP_STEP_BY_STEP_FUZZY_PIPELINE.out.plots
    objects  = BIOC_DFP_STEP_BY_STEP_FUZZY_PIPELINE.out.objects
    versions = BIOC_DFP_STEP_BY_STEP_FUZZY_PIPELINE.out.versions
}
