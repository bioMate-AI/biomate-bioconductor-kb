#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Rfastp — custom_trimming_and_filtering
// Perform quality control and trimming with customized quality cutoffs, sliding window parameters, and specific adapter sequences.
// Input: se_read1
// Container: quay.io/biocontainers/bioconductor-rfastp:1.20.1--r45ha27e39d_0
// Requires: Rfastp, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Run rfastp with custom parameters for front/tail trimming, window sizes, minimum read length, and adapter sequences

nextflow.enable.dsl = 2

process BIOC_RFASTP_CUSTOM_TRIMMING_AND_FILTERING {
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
    .bm_deps <- c("Rfastp", "ggplot2")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load required libraries
    library(Rfastp)
    library(ggplot2)
    
    # Define input file from the working directory
    se_read1 <- "se_read1"
    
    # Verify input file existence
    if (!file.exists(se_read1)) {
      stop(paste("Required input file 'se_read1' not found in the working directory:", getwd()))
    }
    
    # Define output prefix
    outputPrefix <- "trimmed"
    
    # Run rfastp with custom parameters for front/tail trimming, window sizes, 
    # minimum read length, and adapter sequences exactly as documented
    clipr_json_report <- rfastp(read1 = se_read1, 
        outputFastq = paste0(outputPrefix, '_clipr'),
        disableTrimPolyG = TRUE,
        cutLowQualFront = TRUE,
        cutFrontWindowSize = 29,
        cutFrontMeanQual = 20,
        cutLowQualTail = TRUE,
        cutTailWindowSize = 1,
        cutTailMeanQual = 5,
        minReadLength = 29,
        adapterSequenceRead1 = 'GTGTCAGTCACTTCCAGCGG'
    )
    
    # Save the JSON report object
    saveRDS(clipr_json_report, file = "clipr_json_report.rds")
    
    # Generate and save QC Summary Table
    dfsummary <- qcSummary(clipr_json_report)
    write.csv(dfsummary, file = "qc_summary.csv", row.names = FALSE)
    
    # Generate and save Trim Summary Table
    dfTrim <- trimSummary(clipr_json_report)
    write.csv(dfTrim, file = "trim_summary.csv", row.names = FALSE)
    
    # Generate and save Base Quality Plot
    p1 <- curvePlot(clipr_json_report)
    ggsave("base_quality_plot.pdf", plot = p1, width = 8, height = 6)
    
    # Generate and save GC Content Plot
    p2 <- curvePlot(clipr_json_report, curve = "content_curves")
    ggsave("gc_content_plot.pdf", plot = p2, width = 8, height = 6)

    writeLines(c(
        '"BIOC_RFASTP_CUSTOM_TRIMMING_AND_FILTERING":',
        paste0('    Rfastp: ', as.character(packageVersion('Rfastp')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_trimming_and_filtering.csv versions.yml
    """
}

workflow BIOC_RFASTP_CUSTOM_TRIMMING_AND_FILTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ se_read1 ] ]

    main:
    BIOC_RFASTP_CUSTOM_TRIMMING_AND_FILTERING(ch_input)

    emit:
    tables   = BIOC_RFASTP_CUSTOM_TRIMMING_AND_FILTERING.out.tables
    plots    = BIOC_RFASTP_CUSTOM_TRIMMING_AND_FILTERING.out.plots
    objects  = BIOC_RFASTP_CUSTOM_TRIMMING_AND_FILTERING.out.objects
    versions = BIOC_RFASTP_CUSTOM_TRIMMING_AND_FILTERING.out.versions
}
