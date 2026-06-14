#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: evaluomeR — metric_reliability_evaluation
// Evaluate the reliability of bioinformatics metrics by analyzing their correlations, clustering stability, and classification goodness across a range of cluster 
// Input: SummarizedExperiment
// Container: quay.io/biocontainers/bioconductor-evaluomer:1.26.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, evaluomeR
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Calculate Pearson correlation coefficients between metrics using metricsCorrelations
//  * 2. [Core Analysis] Analyze clustering stability for a single k or a range of k values using stability or stabilityRange
//  * 3. [Core Analysis] Assess goodness of classifications (silhouette width) for a single k or a range of k values using quality or qualityRange
//  * 4. [Core Analysis] Retrieve specific data from quality range results using getDataQualityRange
//  * 5. [Core Analysis] Determine the optimal value of k for each metric using getOptimalKValue

nextflow.enable.dsl = 2

process BIOC_EVALUOMER_METRIC_RELIABILITY_EVALUATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("evaluomeR", "SummarizedExperiment")
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
        library(SummarizedExperiment)
library(evaluomeR)
    
    # Read user input
    if (!file.exists("SummarizedExperiment.rds")) {
      stop("Error: 'SummarizedExperiment.rds' not found in the working directory.")
    }
    rnaMetrics <- readRDS("SummarizedExperiment.rds")
    ontMetrics <- rnaMetrics
    
    # Open PDF to capture all generated plots
    pdf("evaluomeR_plots.pdf", width = 11, height = 8.5)
    
    # 1. Calculate Pearson correlation coefficients between metrics
    message("Calculating metrics correlations...")
    correlationSE <- metricsCorrelations(rnaMetrics, margins =  c(4,4,12,10))
    saveRDS(correlationSE, "correlationSE.rds")
    if (length(assays(correlationSE)) > 0) {
      write.csv(as.data.frame(assay(correlationSE, 1)), "correlation_matrix.csv", row.names = TRUE)
    }
    
    # 2. Analyze clustering stability for a single k
    message("Analyzing stability for k=2...")
    stabilityData <- stability(rnaMetrics, k=2, bs = 100)
    saveRDS(stabilityData, "stabilityData_k2.rds")
    
    # 3. Analyze clustering stability for a range of k values
    message("Analyzing stability range k=2..4...")
    stabilityRangeData = stabilityRange(rnaMetrics, k.range=c(2,4), bs = 100)
    saveRDS(stabilityRangeData, "stabilityRangeData.rds")
    
    # 4. Assess goodness of classifications (silhouette width) for a single k
    message("Assessing quality for k=4...")
    tryCatch({
      qualityData = quality(rnaMetrics, k = 4)
      saveRDS(qualityData, "qualityData_k4.rds")
    }, error = function(e) {
      message("Warning: quality for k=4 failed (possibly due to insufficient instances): ", e\$message)
    })
    
    # 5. Assess goodness of classifications for a range of k values
    message("Assessing quality range k=4..6...")
    k.range = c(4,6)
    tryCatch({
      qualityRangeData = qualityRange(rnaMetrics, k.range)
      saveRDS(qualityRangeData, "qualityRangeData.rds")
      
      # Retrieve specific data from quality range results
      k5Data = getDataQualityRange(qualityRangeData, 5)
      saveRDS(k5Data, "k5Data.rds")
    }, error = function(e) {
      message("Warning: qualityRange for k=4..6 failed: ", e\$message)
    })
    
    # 6. Determine the optimal value of k for each metric
    message("Determining optimal k value...")
    stabilityData <- stabilityRange(data=ontMetrics, k.range=c(2,4), bs=20, getImages = FALSE, seed=100)
    qualityData <- qualityRange(data=ontMetrics, k.range=c(2,4), getImages = FALSE, seed=100)
    
    kOptTable <- getOptimalKValue(stabilityData, qualityData)
    write.csv(kOptTable, "kOptTable_default.csv", row.names = TRUE)
    
    kOptTable <- getOptimalKValue(stabilityData, qualityData, k.range=c(3,4))
    write.csv(kOptTable, "kOptTable_range_3_4.csv", row.names = TRUE)
    
    # Close PDF device
    dev.off()
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_EVALUOMER_METRIC_RELIABILITY_EVALUATION":',
        paste0('    evaluomeR: ', as.character(packageVersion('evaluomeR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_metric_reliability_evaluation.csv versions.yml
    """
}

workflow BIOC_EVALUOMER_METRIC_RELIABILITY_EVALUATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ SummarizedExperiment ] ]

    main:
    BIOC_EVALUOMER_METRIC_RELIABILITY_EVALUATION(ch_input)

    emit:
    tables   = BIOC_EVALUOMER_METRIC_RELIABILITY_EVALUATION.out.tables
    plots    = BIOC_EVALUOMER_METRIC_RELIABILITY_EVALUATION.out.plots
    objects  = BIOC_EVALUOMER_METRIC_RELIABILITY_EVALUATION.out.objects
    versions = BIOC_EVALUOMER_METRIC_RELIABILITY_EVALUATION.out.versions
}
