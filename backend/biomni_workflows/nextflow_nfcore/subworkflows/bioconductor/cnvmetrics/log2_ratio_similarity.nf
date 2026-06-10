#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CNVMetrics — log2_ratio_similarity
// Calculate and visualize similarity metrics (Weighted Euclidean Distance) using continuous log2 ratio values.
// Input: copy_number_log2.txt
// Container: quay.io/biocontainers/bioconductor-cnvmetrics:1.14.2--r45hdfd78af_0
// R packages: CNVMetrics, GenomicRanges
// Bioconductor: 3.20 | R: 4.4
// Requires: CNVMetrics, GenomicRanges
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the copy number log2 ratio file into a data.frame
//  * 2. [Core Analysis] Convert the data.frame to a GRangesList using GenomicRanges::makeGRangesListFromDataFrame()
//  * 3. [Core Analysis] Calculate log2 ratio metrics using calculateLog2ratioMetric()
//  * 4. [Visualization & Output] Visualize the similarity metrics as a heatmap using plotMetric()

nextflow.enable.dsl = 2

process BIOC_CNVMETRICS_LOG2_RATIO_SIMILARITY {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20"

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
    .bm_deps <- c("CNVMetrics", "GenomicRanges")
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
    library(GenomicRanges)
    library(CNVMetrics)
    
    # Set seed for reproducibility as recommended in the documentation
    set.seed(121234)
    
    # 1. Load the copy number log2 ratio file into a data.frame
    input_file <- "copy_number_log2.txt"
    if (!file.exists(input_file)) {
      stop(paste("Required input file missing:", input_file))
    }
    
    calls <- read.table(input_file, header=TRUE, sep="\t")
    
    # 2. Convert the data.frame to a GRangesList using GenomicRanges::makeGRangesListFromDataFrame()
    grlog <- GenomicRanges::makeGRangesListFromDataFrame(df=calls, 
        split.field="ID", keep.extra.columns=TRUE)
    
    # 3. Calculate log2 ratio metrics using calculateLog2ratioMetric()
    metricLog <- calculateLog2ratioMetric(segmentData=grlog, 
                                  method="weightedEuclideanDistance", nJobs=1)
    
    # Save the complete metric object as an RDS file
    saveRDS(metricLog, file="metric_log2_ratio.rds")
    
    # Export the similarity metric matrix as a CSV file
    tryCatch({
      if (!is.null(metricLog\$LOG2RATIO)) {
        write.csv(as.data.frame(metricLog\$LOG2RATIO), "metric_log2_ratio_matrix.csv", row.names=TRUE)
      } else {
        write.csv(as.data.frame(as.matrix(metricLog)), "metric_log2_ratio_matrix.csv", row.names=TRUE)
      }
    }, error = function(e) {
      message("Note: Could not export metric matrix to CSV directly. Saving RDS instead.")
    })
    
    # 4. Visualize the similarity metrics as a heatmap using plotMetric() and save to PDF
    pdf("similarity_heatmap.pdf", width=7, height=7)
    plotMetric(metricLog)
    dev.off()

    writeLines(c(
        '"BIOC_CNVMETRICS_LOG2_RATIO_SIMILARITY":',
        paste0('    CNVMetrics: ', as.character(packageVersion('CNVMetrics')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_log2_ratio_similarity.csv versions.yml
    """
}

workflow BIOC_CNVMETRICS_LOG2_RATIO_SIMILARITY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ copy_number_log2.txt ] ]

    main:
    BIOC_CNVMETRICS_LOG2_RATIO_SIMILARITY(ch_input)

    emit:
    tables   = BIOC_CNVMETRICS_LOG2_RATIO_SIMILARITY.out.tables
    plots    = BIOC_CNVMETRICS_LOG2_RATIO_SIMILARITY.out.plots
    objects  = BIOC_CNVMETRICS_LOG2_RATIO_SIMILARITY.out.objects
    versions = BIOC_CNVMETRICS_LOG2_RATIO_SIMILARITY.out.versions
}
