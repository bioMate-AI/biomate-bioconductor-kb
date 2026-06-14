#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rfastp — umi_processing
// Preprocess paired-end FASTQ files containing Unique Molecular Identifiers (UMIs), extracting and appending them to read headers.
// Input: reads1.fastq.gz, reads2.fastq.gz
// Container: quay.io/biocontainers/bioconductor-rfastp:1.20.1--r45ha27e39d_0
// R packages: Rfastp
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RFASTP_UMI_PROCESSING {
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
    .bm_deps <- c("Rfastp")
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
    pe_read1 <- "reads1.fastq.gz"
    pe_read2 <- "reads2.fastq.gz"
    
    # Verify input files exist
    if (!file.exists(pe_read1) || !file.exists(pe_read2)) {
      stop("Error: Input files 'reads1.fastq.gz' and/or 'reads2.fastq.gz' must exist in the working directory.")
    }
    
    # Define output prefix in the working directory
    outputPrefix <- "umi_processed"
    
    # ==========================================
    # --- Run rfastp with standard UMI extraction parameters ---
    # ==========================================
    umi_json_report <- rfastp(read1 = pe_read1, read2 = pe_read2, 
        outputFastq = paste0(outputPrefix, '_umi1'), umi = TRUE, umiLoc = "read1",
        umiLength = 16)
    
    # Save Stage 1 results
    saveRDS(umi_json_report, file = "umi1_report.rds")
    
    # Extract and save summaries
    dfsummary1 <- qcSummary(umi_json_report)
    write.csv(dfsummary1, file = "umi1_qc_summary.csv", row.names = FALSE)
    
    dfTrim1 <- trimSummary(umi_json_report)
    write.csv(dfTrim1, file = "umi1_trim_summary.csv", row.names = FALSE)
    
    # Generate and save plots
    pdf("umi1_plots.pdf", width = 8, height = 6)
    tryCatch({
      p1 <- curvePlot(umi_json_report)
      print(p1)
    }, error = function(e) {
      warning("Could not generate base quality plot for Stage 1: ", e\$message)
    })
    
    tryCatch({
      p2 <- curvePlot(umi_json_report, curve = "content_curves")
      print(p2)
    }, error = function(e) {
      warning("Could not generate GC content plot for Stage 1: ", e\$message)
    })
    dev.off()
    
    
    # ==========================================
    # --- Run rfastp with customized UMI prefix and location ---
    # ==========================================
    umi_json_report <- rfastp(read1 = pe_read1, read2 = pe_read2, 
        outputFastq = paste0(outputPrefix, '_umi2'), umi = TRUE, umiLoc = "read1",
        umiLength = 16, umiPrefix = "#", umiNoConnection = TRUE, 
        umiIgnoreSeqNameSpace = TRUE)
    
    # Save Stage 2 results
    saveRDS(umi_json_report, file = "umi2_report.rds")
    
    # Extract and save summaries
    dfsummary2 <- qcSummary(umi_json_report)
    write.csv(dfsummary2, file = "umi2_qc_summary.csv", row.names = FALSE)
    
    dfTrim2 <- trimSummary(umi_json_report)
    write.csv(dfTrim2, file = "umi2_trim_summary.csv", row.names = FALSE)
    
    # Generate and save plots
    pdf("umi2_plots.pdf", width = 8, height = 6)
    tryCatch({
      p3 <- curvePlot(umi_json_report)
      print(p3)
    }, error = function(e) {
      warning("Could not generate base quality plot for Stage 2: ", e\$message)
    })
    
    tryCatch({
      p4 <- curvePlot(umi_json_report, curve = "content_curves")
      print(p4)
    }, error = function(e) {
      warning("Could not generate GC content plot for Stage 2: ", e\$message)
    })
    dev.off()
    
    message("Pipeline completed successfully. Outputs written to working directory.")

    writeLines(c(
        '"BIOC_RFASTP_UMI_PROCESSING":',
        paste0('        rfastp: ', as.character(packageVersion("rfastp")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_umi_processing.csv versions.yml
    """
}

workflow BIOC_RFASTP_UMI_PROCESSING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ reads1.fastq.gz, reads2.fastq.gz ] ]

    main:
    BIOC_RFASTP_UMI_PROCESSING(ch_input)

    emit:
    tables   = BIOC_RFASTP_UMI_PROCESSING.out.tables
    plots    = BIOC_RFASTP_UMI_PROCESSING.out.plots
    objects  = BIOC_RFASTP_UMI_PROCESSING.out.objects
    versions = BIOC_RFASTP_UMI_PROCESSING.out.versions
}
