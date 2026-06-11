#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Rfastp — paired_end_qc_and_merging
// Perform quality control, trimming, and optional merging of paired-end FASTQ files.
// Input: pe_read1, pe_read2
// Container: quay.io/biocontainers/bioconductor-rfastp:1.20.1--r45ha27e39d_0
// R packages: Rfastp, ggplot2
// Bioconductor: 3.20 | R: 4.4
// Requires: Rfastp, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run rfastp on paired-end reads
//  * 2. [Core Analysis] Run rfastp with merge = TRUE to merge overlapping paired-end reads after QC

nextflow.enable.dsl = 2

process BIOC_RFASTP_PAIRED_END_QC_AND_MERGING {
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
    library(Rfastp)
    
    # Define input files from the working directory
    pe_read1 <- "pe_read1"
    pe_read2 <- "pe_read2"
    
    # Robust check for common extensions if exact names do not exist
    if (!file.exists(pe_read1)) {
      for (ext in c(".fastq.gz", ".fq.gz", ".fastq", ".fq")) {
        if (file.exists(paste0("pe_read1", ext))) {
          pe_read1 <- paste0("pe_read1", ext)
          break
        }
      }
    }
    
    if (!file.exists(pe_read2)) {
      for (ext in c(".fastq.gz", ".fq.gz", ".fastq", ".fq")) {
        if (file.exists(paste0("pe_read2", ext))) {
          pe_read2 <- paste0("pe_read2", ext)
          break
        }
      }
    }
    
    # Verify files exist before running
    if (!file.exists(pe_read1) || !file.exists(pe_read2)) {
      stop("Input files 'pe_read1' and/or 'pe_read2' (or with common fastq extensions) not found in the working directory.")
    }
    
    # Define output prefix
    outputPrefix <- "rfastp_output"
    
    # 1. Run rfastp on paired-end reads
    pe_json_report <- rfastp(read1 = pe_read1, read2 = pe_read2,
        outputFastq = paste0(outputPrefix, "_pe"))
    
    # 2. Run rfastp with merge = TRUE to merge overlapping paired-end reads after QC
    pe_merge_json_report <- rfastp(read1 = pe_read1, read2 = pe_read2, merge = TRUE,
        outputFastq = paste0(outputPrefix, '_unpaired'),
        mergeOut = paste0(outputPrefix, "_merged.fastq.gz"))
    
    # Write meaningful outputs
    # Save report objects
    saveRDS(pe_json_report, file = "pe_json_report.rds")
    saveRDS(pe_merge_json_report, file = "pe_merge_json_report.rds")
    
    # Extract and save summaries
    dfsummary <- qcSummary(pe_json_report)
    write.csv(dfsummary, file = "qc_summary.csv", row.names = FALSE)
    
    dfTrim <- trimSummary(pe_json_report)
    write.csv(dfTrim, file = "trim_summary.csv", row.names = FALSE)
    
    # Generate and save plots
    tryCatch({
      library(ggplot2)
      p1 <- curvePlot(pe_json_report)
      ggsave("base_quality_plot.pdf", plot = p1, width = 8, height = 6)
    }, error = function(e) {
      message("Could not generate base quality plot: ", e\$message)
    })
    
    tryCatch({
      library(ggplot2)
      p2 <- curvePlot(pe_json_report, curve="content_curves")
      ggsave("gc_content_plot.pdf", plot = p2, width = 8, height = 6)
    }, error = function(e) {
      message("Could not generate GC content plot: ", e\$message)
    })

    writeLines(c(
        '"BIOC_RFASTP_PAIRED_END_QC_AND_MERGING":',
        paste0('    Rfastp: ', as.character(packageVersion('Rfastp')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_paired_end_qc_and_merging.csv versions.yml
    """
}

workflow BIOC_RFASTP_PAIRED_END_QC_AND_MERGING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pe_read1, pe_read2 ] ]

    main:
    BIOC_RFASTP_PAIRED_END_QC_AND_MERGING(ch_input)

    emit:
    tables   = BIOC_RFASTP_PAIRED_END_QC_AND_MERGING.out.tables
    plots    = BIOC_RFASTP_PAIRED_END_QC_AND_MERGING.out.plots
    objects  = BIOC_RFASTP_PAIRED_END_QC_AND_MERGING.out.objects
    versions = BIOC_RFASTP_PAIRED_END_QC_AND_MERGING.out.versions
}
