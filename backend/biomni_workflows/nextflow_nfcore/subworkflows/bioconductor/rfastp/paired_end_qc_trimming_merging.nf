#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rfastp — paired_end_qc_trimming_merging
// Perform quality control, adapter trimming, and optional merging on paired-end FASTQ data, followed by extracting summary statistics.
// Input: reads1.fastq.gz, reads2.fastq.gz
// Container: quay.io/biocontainers/bioconductor-rfastp:1.20.1--r45ha27e39d_0
// R packages: Rfastp, ggplot2
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_RFASTP_PAIRED_END_QC_TRIMMING_MERGING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-rfastp:1.20.1--r45ha27e39d_0"

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
    
    # Define input files from the working directory as specified
    pe_read1 <- "reads1.fastq.gz"
    pe_read2 <- "reads2.fastq.gz"
    
    # Verify input files exist
    if (!file.exists(pe_read1)) {
      stop(paste("Required input file missing:", pe_read1))
    }
    if (!file.exists(pe_read2)) {
      stop(paste("Required input file missing:", pe_read2))
    }
    
    # Define output prefix for output FASTQ files
    outputPrefix <- "rfastp_output"
    
    # --- Run rfastp on paired-end FASTQ files ---
    pe_json_report <- rfastp(read1 = pe_read1, read2 = pe_read2,
        outputFastq = paste0(outputPrefix, "_pe"))
    
    # --- Run rfastp with read merging enabled ---
    pe_merge_json_report <- rfastp(read1 = pe_read1, read2 = pe_read2, merge = TRUE,
        outputFastq = paste0(outputPrefix, '_unpaired'),
        mergeOut = paste0(outputPrefix, "_merged.fastq.gz"))
    
    # --- Extract QC and trimming summaries ---
    dfsummary <- qcSummary(pe_json_report)
    dfTrim <- trimSummary(pe_json_report)
    
    # Write meaningful results to output files
    write.csv(dfsummary, "qc_summary.csv", row.names = FALSE)
    write.csv(dfTrim, "trim_summary.csv", row.names = FALSE)
    
    # Save report objects as RDS
    saveRDS(pe_json_report, "pe_json_report.rds")
    saveRDS(pe_merge_json_report, "pe_merge_json_report.rds")
    
    # Generate and save quality plots
    tryCatch({
      library(ggplot2)
      p1 <- curvePlot(pe_json_report)
      ggsave("base_quality_plot.pdf", plot = p1, width = 8, height = 6)
      
      p2 <- curvePlot(pe_json_report, curve = "content_curves")
      ggsave("gc_content_plot.pdf", plot = p2, width = 8, height = 6)
    }, error = function(e) {
      message("Plot generation skipped or failed: ", e\$message)
    })

    writeLines(c(
        '"BIOC_RFASTP_PAIRED_END_QC_TRIMMING_MERGING":',
        paste0('        rfastp: ', as.character(packageVersion("rfastp")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_paired_end_qc_trimming_merging.csv versions.yml
    """
}

workflow BIOC_RFASTP_PAIRED_END_QC_TRIMMING_MERGING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ reads1.fastq.gz, reads2.fastq.gz ] ]

    main:
    BIOC_RFASTP_PAIRED_END_QC_TRIMMING_MERGING(ch_input)

    emit:
    tables   = BIOC_RFASTP_PAIRED_END_QC_TRIMMING_MERGING.out.tables
    plots    = BIOC_RFASTP_PAIRED_END_QC_TRIMMING_MERGING.out.plots
    objects  = BIOC_RFASTP_PAIRED_END_QC_TRIMMING_MERGING.out.objects
    versions = BIOC_RFASTP_PAIRED_END_QC_TRIMMING_MERGING.out.versions
}
