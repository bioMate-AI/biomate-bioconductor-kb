#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: AffyRNADegradation — integrated_calibration_pipeline
// Perform probe-level normalization using VSN, correct for probe positional bias, and compute summarized expression measures.
// Input: AmpData
// Container: quay.io/biocontainers/bioconductor-affyrnadegradation:1.56.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: AffyRNADegradation, Biobase, affy, vsn
// Visualizations: box plot
// QC: variance-stabilizing normalization
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Normalize raw AffyBatch data using VSN
//  * 2. [Core Analysis] Correct for probe positional bias on the normalized data
//  * 3. [Visualization & Output] Summarize probe intensities into expression sets using median polish

nextflow.enable.dsl = 2

process BIOC_AFFYRNADEGRADATION_INTEGRATED_CALIBRATION_PIPELINE {
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
    .bm_deps <- c("AffyRNADegradation", "affy", "vsn", "Biobase")
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
    library(AffyRNADegradation)
    library(affy)
    library(vsn)
    library(Biobase)
    
    # 1. Read the input AmpData object from the working directory
    if (file.exists("AmpData.rds")) {
      AmpData <- readRDS("AmpData.rds")
    } else if (file.exists("AmpData.RData")) {
      env <- new.env()
      load("AmpData.RData", envir = env)
      if ("AmpData" %in% names(env)) {
        AmpData <- env\$AmpData
      } else {
        load("AmpData.RData")
      }
    } else {
      stop("Error: Required input file 'AmpData.rds' or 'AmpData.RData' not found in the working directory.")
    }
    
    # Verify that the loaded object is of class AffyBatch
    if (!inherits(AmpData, "AffyBatch")) {
      stop("Error: Loaded object 'AmpData' is not of class 'AffyBatch'.")
    }
    
    # 2. Normalize raw AffyBatch data using VSN
    # (Reproducing the exact documented call)
    affydata.vsn <- do.call(affy:::normalize, c(alist(AmpData, "vsn"), NULL))
    
    # 3. Correct for probe positional bias on the normalized data
    # (Reproducing the exact documented call)
    affydata.vsn <- afbatch(RNADegradation(affydata.vsn))
    
    # 4. Summarize probe intensities into expression sets using median polish
    # (Reproducing the exact documented call)
    expr <- computeExprSet(affydata.vsn, summary.method="medianpolish", pmcorrect.method="pmonly")
    
    # 5. Write outputs to the working directory
    # Save the complete ExpressionSet object
    saveRDS(expr, file = "normalized_expression_set.rds")
    
    # Export the expression matrix as a CSV file
    expr_matrix <- exprs(expr)
    write.csv(expr_matrix, file = "expression_matrix.csv", row.names = TRUE)
    
    # Generate a diagnostic boxplot of the normalized and corrected expression values
    pdf("expression_summary.pdf", width = 8, height = 6)
    boxplot(expr_matrix, 
            main = "VSN Normalized & Positional Bias Corrected Expression",
            las = 2, 
            col = "skyblue", 
            ylab = "Log2 Intensity")
    dev.off()

    writeLines(c(
        '"BIOC_AFFYRNADEGRADATION_INTEGRATED_CALIBRATION_PIPELINE":',
        paste0('    AffyRNADegradation: ', as.character(packageVersion('AffyRNADegradation')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_integrated_calibration_pipeline.csv versions.yml
    """
}

workflow BIOC_AFFYRNADEGRADATION_INTEGRATED_CALIBRATION_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ AmpData ] ]

    main:
    BIOC_AFFYRNADEGRADATION_INTEGRATED_CALIBRATION_PIPELINE(ch_input)

    emit:
    tables   = BIOC_AFFYRNADEGRADATION_INTEGRATED_CALIBRATION_PIPELINE.out.tables
    plots    = BIOC_AFFYRNADEGRADATION_INTEGRATED_CALIBRATION_PIPELINE.out.plots
    objects  = BIOC_AFFYRNADEGRADATION_INTEGRATED_CALIBRATION_PIPELINE.out.objects
    versions = BIOC_AFFYRNADEGRADATION_INTEGRATED_CALIBRATION_PIPELINE.out.versions
}
