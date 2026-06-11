#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CNVMetrics — cnv_status_calls_similarity
// Calculate and visualize similarity metrics (Sørensen, Szymkiewicz-Simpson, or Jaccard) using discrete CNV status calls.
// Input: copy_number_calls.txt
// Container: quay.io/biocontainers/bioconductor-cnvmetrics:1.14.2--r45hdfd78af_0
// R packages: CNVMetrics, GenomicRanges, knitr
// Bioconductor: 3.20 | R: 4.4
// Requires: CNVMetrics, GenomicRanges
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the copy number calls file into a data.frame
//  * 2. [Core Analysis] Convert the data.frame to a GRangesList using GenomicRanges::makeGRangesListFromDataFrame()
//  * 3. [Core Analysis] Calculate overlap metrics using calculateOverlapMetric()
//  * 4. [Visualization & Output] Visualize the similarity metrics as a heatmap using plotMetric()

nextflow.enable.dsl = 2

process BIOC_CNVMETRICS_CNV_STATUS_CALLS_SIMILARITY {
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
    .bm_deps <- c("CNVMetrics", "GenomicRanges", "knitr")
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
    
    # 1. Load the copy number calls file into a data.frame
    input_file <- "copy_number_calls.txt"
    if (!file.exists(input_file)) {
      stop(paste("Required input file missing:", input_file))
    }
    calls <- read.table(input_file, header=TRUE, sep="\t")
    
    # 2. Convert the data.frame to a GRangesList using GenomicRanges::makeGRangesListFromDataFrame()
    grl <- GenomicRanges::makeGRangesListFromDataFrame(calls, 
        split.field="ID", keep.extra.columns=TRUE)
    
    # 3. Calculate overlap metrics using calculateOverlapMetric()
    metric <- calculateOverlapMetric(segmentData=grl, method="sorensen", nJobs=1)
    
    # Save the metric object as an RDS file
    saveRDS(metric, file="overlap_metric.rds")
    
    # Export the metric matrices as CSV files for downstream analysis
    if (!is.null(metric\$AMPLIFICATION)) {
      write.csv(as.data.frame(metric\$AMPLIFICATION), "sorensen_amplification_metric.csv", row.names=TRUE)
    }
    if (!is.null(metric\$DELETION)) {
      write.csv(as.data.frame(metric\$DELETION), "sorensen_deletion_metric.csv", row.names=TRUE)
    }
    
    # 4. Visualize the similarity metrics as a heatmap using plotMetric()
    pdf("sorensen_amplification_heatmap.pdf", width=7, height=7)
    plotMetric(metric, type="AMPLIFICATION")
    dev.off()

    writeLines(c(
        '"BIOC_CNVMETRICS_CNV_STATUS_CALLS_SIMILARITY":',
        paste0('    CNVMetrics: ', as.character(packageVersion('CNVMetrics')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cnv_status_calls_similarity.csv versions.yml
    """
}

workflow BIOC_CNVMETRICS_CNV_STATUS_CALLS_SIMILARITY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ copy_number_calls.txt ] ]

    main:
    BIOC_CNVMETRICS_CNV_STATUS_CALLS_SIMILARITY(ch_input)

    emit:
    tables   = BIOC_CNVMETRICS_CNV_STATUS_CALLS_SIMILARITY.out.tables
    plots    = BIOC_CNVMETRICS_CNV_STATUS_CALLS_SIMILARITY.out.plots
    objects  = BIOC_CNVMETRICS_CNV_STATUS_CALLS_SIMILARITY.out.objects
    versions = BIOC_CNVMETRICS_CNV_STATUS_CALLS_SIMILARITY.out.versions
}
