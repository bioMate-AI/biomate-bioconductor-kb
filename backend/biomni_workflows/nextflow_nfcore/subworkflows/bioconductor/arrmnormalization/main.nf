#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ARRmNormalization — arrm_normalization_and_visualization
// Perform Adaptive Robust Regression normalization on 450k methylation data and visualize technical artifacts.
// Input: betaMatrix, greenControlMatrix, redControlMatrix, sampleNames
// Container: quay.io/biocontainers/bioconductor-arrmnormalization:1.50.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ARRmNormalization
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Extract background intensities using getBackground
//  * 2. [Core Analysis] Extract physical chip and position information using getDesignInfo
//  * 3. [Core Analysis] Perform ARRm normalization using normalizeARRm
//  * 4. [Core Analysis] Extract beta value distribution quantiles using getQuantiles
//  * 5. [Visualization & Output] Generate diagnostic plots for background and dye bias effects using quantilePlots
//  * 6. [Visualization & Output] Generate diagnostic plots for spatial position effects using positionPlots
//  * 7. [Core Analysis] Extract robust regression coefficients using getCoefficients

nextflow.enable.dsl = 2

process BIOC_ARRMNORMALIZATION_ARRM_NORMALIZATION_AND_VISUALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("ARRmNormalization")
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
    
    # Load required library
    library(ARRmNormalization)
    
    # ==========================================
    # 1. READ USER INPUT FILES
    # ==========================================
    
    # Read betaMatrix
    if (file.exists("betaMatrix.rds")) {
      betaMatrix <- readRDS("betaMatrix.rds")
    } else if (file.exists("betaMatrix.csv")) {
      betaMatrix <- as.matrix(read.csv("betaMatrix.csv", row.names = 1, check.names = FALSE))
    } else {
      stop("Error: betaMatrix file not found (expected betaMatrix.rds or betaMatrix.csv in the working directory).")
    }
    
    # Read greenControlMatrix
    if (file.exists("greenControlMatrix.rds")) {
      greenControlMatrix <- readRDS("greenControlMatrix.rds")
    } else if (file.exists("greenControlMatrix.csv")) {
      greenControlMatrix <- as.matrix(read.csv("greenControlMatrix.csv", row.names = 1, check.names = FALSE))
    } else {
      stop("Error: greenControlMatrix file not found (expected greenControlMatrix.rds or greenControlMatrix.csv).")
    }
    
    # Read redControlMatrix
    if (file.exists("redControlMatrix.rds")) {
      redControlMatrix <- readRDS("redControlMatrix.rds")
    } else if (file.exists("redControlMatrix.csv")) {
      redControlMatrix <- as.matrix(read.csv("redControlMatrix.csv", row.names = 1, check.names = FALSE))
    } else {
      stop("Error: redControlMatrix file not found (expected redControlMatrix.rds or redControlMatrix.csv).")
    }
    
    # Read sampleNames
    if (file.exists("sampleNames.rds")) {
      sampleNames <- readRDS("sampleNames.rds")
    } else if (file.exists("sampleNames.txt")) {
      sampleNames <- readLines("sampleNames.txt")
    } else if (file.exists("sampleNames.csv")) {
      sampleNames <- read.csv("sampleNames.csv", header = FALSE)[[1]]
    } else {
      stop("Error: sampleNames file not found (expected sampleNames.rds, sampleNames.txt, or sampleNames.csv).")
    }
    
    # Ensure sampleNames is a character vector
    sampleNames <- as.character(sampleNames)
    
    # ==========================================
    # 2. PIPELINE EXECUTION (DOCUMENTED WORKFLOW)
    # ==========================================
    
    # Stage 1: Extract background intensities using getBackground
    backgroundInfo <- getBackground(greenControlMatrix, redControlMatrix)
    write.csv(backgroundInfo, "backgroundInfo.csv", row.names = TRUE)
    
    # Stage 2: Extract physical chip and position information using getDesignInfo
    designInfo <- getDesignInfo(sampleNames)
    write.csv(designInfo, "designInfo.csv", row.names = TRUE)
    
    # Stage 3: Perform ARRm normalization using normalizeARRm
    normMatrix <- normalizeARRm(betaMatrix=betaMatrix, designInfo=designInfo, backgroundInfo=backgroundInfo, outliers.perc=0.1)
    saveRDS(normMatrix, "normMatrix.rds")
    # Save a preview of the normalized matrix
    write.csv(head(normMatrix, 100), "normMatrix_preview.csv", row.names = TRUE)
    
    # Stage 4: Extract beta value distribution quantiles using getQuantiles
    quantiles=getQuantiles(betaMatrix)
    saveRDS(quantiles, "quantiles.rds")
    
    # Stage 5: Generate diagnostic plots for background and dye bias effects using quantilePlots
    # This function automatically writes to "quantilePlots.pdf" in the working directory
    quantilePlots(quantiles, backgroundInfo, designInfo)
    
    # Stage 6: Generate diagnostic plots for spatial position effects using positionPlots
    # This function automatically writes to "positionPlots.pdf" in the working directory
    positionPlots(quantiles, designInfo, percentiles=c(25, 50, 75))
    
    # Stage 7: Extract robust regression coefficients using getCoefficients
    coefficients <- getCoefficients(quantiles, designInfo, backgroundInfo, outliers.perc=0.02)
    saveRDS(coefficients, "coefficients.rds")

    writeLines(c(
        '"BIOC_ARRMNORMALIZATION_ARRM_NORMALIZATION_AND_VISUALIZATION":',
        paste0('    ARRmNormalization: ', as.character(packageVersion('ARRmNormalization')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_arrm_normalization_and_visualization.csv versions.yml
    """
}

workflow BIOC_ARRMNORMALIZATION_ARRM_NORMALIZATION_AND_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ betaMatrix, greenControlMatrix, redControlMatrix, sampleNames ] ]

    main:
    BIOC_ARRMNORMALIZATION_ARRM_NORMALIZATION_AND_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_ARRMNORMALIZATION_ARRM_NORMALIZATION_AND_VISUALIZATION.out.tables
    plots    = BIOC_ARRMNORMALIZATION_ARRM_NORMALIZATION_AND_VISUALIZATION.out.plots
    objects  = BIOC_ARRMNORMALIZATION_ARRM_NORMALIZATION_AND_VISUALIZATION.out.objects
    versions = BIOC_ARRMNORMALIZATION_ARRM_NORMALIZATION_AND_VISUALIZATION.out.versions
}
