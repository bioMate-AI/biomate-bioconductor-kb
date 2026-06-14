#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CytoMDS — generic_expression_matrices
// Run the CytoMDS visualization workflow using a generic list of standard R expression matrices instead of flowCore objects.
// Input: exprMatrixList, phenoDataExpr
// Container: quay.io/biocontainers/bioconductor-cytomds:1.6.1--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: CytoMDS, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Calculate pairwise EMD distances from the list of expression matrices using pairwiseEMDDist
//  * 2. [Core Analysis] Compute the metric MDS projection using computeMetricMDS
//  * 3. [Visualization & Output] Plot the MDS projection using ggplotSampleMDS
//  * 4. [Visualization & Output] Calculate summary statistics across matrices using channelSummaryStats
//  * 5. [Visualization & Output] Generate faceted bi-plots using ggplotSampleMDSWrapBiplots

nextflow.enable.dsl = 2

process BIOC_CYTOMDS_GENERIC_EXPRESSION_MATRICES {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    .bm_deps <- c("CytoMDS", "ggplot2")
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
        library(CytoMDS)
        library(ggplot2)
        
        # ==========================================
        # 1. Read User Input Files
        # ==========================================
        # The pipeline expects 'exprMatrixList.rds' (a list of standard R matrices)
        # and 'phenoDataExpr.csv' (a data.frame containing sample metadata)
        # to be present in the working directory.
        
        if (!file.exists("exprMatrixList.rds")) {
          stop("Error: 'exprMatrixList.rds' not found in the working directory.")
        }
        if (!file.exists("phenoDataExpr.csv")) {
          stop("Error: 'phenoDataExpr.csv' not found in the working directory.")
        }
        
        exprMatrixList <- readRDS("exprMatrixList.rds")
        phenoDataExpr <- read.csv("phenoDataExpr.csv", stringsAsFactors = TRUE)
        
        # Determine columns for plotting based on available metadata
        label_col <- colnames(phenoDataExpr)[1]
        color_col <- if (ncol(phenoDataExpr) > 1) colnames(phenoDataExpr)[2] else colnames(phenoDataExpr)[1]
        
        # ==========================================
        # 2. Calculate Pairwise EMD Distances
        # ==========================================
        pwDistExpr <- pairwiseEMDDist(
            exprMatrixList
        )
        
        # Save pairwise distance object
        saveRDS(pwDistExpr, file = "pwDistExpr.rds")
        
        # ==========================================
        # 3. Compute Metric MDS Projection
        # ==========================================
        mdsObjExpr <- computeMetricMDS(pwDistExpr, seed = 0)
        show(mdsObjExpr)
        
        # Save MDS object
        saveRDS(mdsObjExpr, file = "mdsObjExpr.rds")
        
        # ==========================================
        # 4. Plot MDS Projection
        # ==========================================
        p12 <- ggplotSampleMDS(
            mdsObjExpr,
            pData = phenoDataExpr,
            projectionAxes = c(1,2),
            pDataForColour = color_col,
            pDataForLabel = label_col
        )
        
        # Save MDS plot
        ggsave("mds_projection_plot.pdf", plot = p12, width = 7, height = 6)
        
        # ==========================================
        # 5. Calculate Summary Statistics Across Matrices
        # ==========================================
        statFunctions <- list(mean = base::mean,
                              std_dev = stats::sd)
        chStatsExpr <- channelSummaryStats(exprMatrixList,
                                           statFUNs  = statFunctions)
        
        # Save summary statistics
        saveRDS(chStatsExpr, file = "channel_stats.rds")
        
        # ==========================================
        # 6. Generate Faceted Bi-plots
        # ==========================================
        p <- CytoMDS::ggplotSampleMDSWrapBiplots(
            mdsObj = mdsObjExpr,
            extVariableList = chStatsExpr,
            pData = phenoDataExpr,
            projectionAxes = c(1,2),
            pDataForColour = color_col,
            displayPointLabels = FALSE,
            repelArrowLabels = TRUE,
            ncol = 2,
            arrowThreshold = 0.9
        )
        
        # Save bi-plot
        ggsave("mds_biplot_wrap.pdf", plot = p, width = 10, height = 8)

    writeLines(c(
        '"BIOC_CYTOMDS_GENERIC_EXPRESSION_MATRICES":',
        paste0('    CytoMDS: ', as.character(packageVersion('CytoMDS')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_generic_expression_matrices.csv versions.yml
    """
}

workflow BIOC_CYTOMDS_GENERIC_EXPRESSION_MATRICES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ exprMatrixList, phenoDataExpr ] ]

    main:
    BIOC_CYTOMDS_GENERIC_EXPRESSION_MATRICES(ch_input)

    emit:
    tables   = BIOC_CYTOMDS_GENERIC_EXPRESSION_MATRICES.out.tables
    plots    = BIOC_CYTOMDS_GENERIC_EXPRESSION_MATRICES.out.plots
    objects  = BIOC_CYTOMDS_GENERIC_EXPRESSION_MATRICES.out.objects
    versions = BIOC_CYTOMDS_GENERIC_EXPRESSION_MATRICES.out.versions
}
