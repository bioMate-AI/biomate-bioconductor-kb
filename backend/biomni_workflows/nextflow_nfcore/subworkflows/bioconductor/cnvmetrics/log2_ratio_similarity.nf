#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CNVMetrics — log2_ratio_similarity
// Calculate and visualize similarity metrics (Weighted Euclidean Distance) using continuous log2 ratio values.
// Input: copy_number_log2.txt
// Container: quay.io/biocontainers/bioconductor-cnvmetrics:1.14.2--r45hdfd78af_0
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
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
