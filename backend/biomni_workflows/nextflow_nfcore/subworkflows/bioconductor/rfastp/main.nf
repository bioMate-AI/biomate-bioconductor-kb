#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rfastp — single_end_qc_trimming
// Perform quality control, adapter trimming, and quality filtering on single-end FASTQ data, followed by generating summary tables and plots.
// Input: Fox3_Std_small.fq.gz
// Container: quay.io/biocontainers/bioconductor-rfastp:1.20.1--r45ha27e39d_0
// R packages: ggplot2, Rfastp
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_RFASTP_SINGLE_END_QC_TRIMMING {
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
    .bm_deps <- c("ggplot2", "Rfastp")
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
    library(Rfastp)
    library(ggplot2)
    
    # Define input file from the working directory
    se_read1 <- "Fox3_Std_small.fq.gz"
    
    # Check if input file exists
    if (!file.exists(se_read1)) {
      stop(paste("Required input file not found in the working directory:", se_read1))
    }
    
    # Define output prefix
    outputPrefix <- "Fox3_Std_small_processed"
    
    # --- Run rfastp on the single-end FASTQ file ---
    se_json_report <- rfastp(read1 = se_read1, 
        outputFastq = paste0(outputPrefix, "_se"), thread = 4)
    
    # --- Generate base quality and GC content plots ---
    p1 <- curvePlot(se_json_report)
    p2 <- curvePlot(se_json_report, curve="content_curves")
    
    # Save plots to a PDF file
    pdf("qc_plots.pdf", width = 10, height = 6)
    print(p1)
    print(p2)
    dev.off()
    
    # --- Extract summary statistics ---
    dfsummary <- qcSummary(se_json_report)
    dfTrim <- trimSummary(se_json_report)
    
    # Save summary tables to CSV
    write.csv(dfsummary, "qc_summary.csv", row.names = FALSE)
    write.csv(dfTrim, "trim_summary.csv", row.names = FALSE)
    
    # Save the JSON report object as RDS
    saveRDS(se_json_report, "se_json_report.rds")

    writeLines(c(
        '"BIOC_RFASTP_SINGLE_END_QC_TRIMMING":',
        paste0('        rfastp: ', as.character(packageVersion("rfastp")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_end_qc_trimming.csv versions.yml
    """
}

workflow BIOC_RFASTP_SINGLE_END_QC_TRIMMING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Fox3_Std_small.fq.gz ] ]

    main:
    BIOC_RFASTP_SINGLE_END_QC_TRIMMING(ch_input)

    emit:
    tables   = BIOC_RFASTP_SINGLE_END_QC_TRIMMING.out.tables
    plots    = BIOC_RFASTP_SINGLE_END_QC_TRIMMING.out.plots
    objects  = BIOC_RFASTP_SINGLE_END_QC_TRIMMING.out.objects
    versions = BIOC_RFASTP_SINGLE_END_QC_TRIMMING.out.versions
}
