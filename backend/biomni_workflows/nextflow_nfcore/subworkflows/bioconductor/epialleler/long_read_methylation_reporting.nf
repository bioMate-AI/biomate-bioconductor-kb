#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: epialleleR — long_read_methylation_reporting
// Preprocess native long-read BAM files containing MM/ML tags and generate cytosine methylation reports.
// Input: longread.bam
// Container: quay.io/biocontainers/bioconductor-epialleler:1.18.0--r45ha27e39d_0
// R packages: epialleleR
// Bioconductor: 3.20 | R: 4.4
// Requires: epialleleR
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Preprocess the long-read BAM file with specific mapping, base quality, and probability thresholds
//  * 2. [Visualization & Output] Generate conventional cytosine reports

nextflow.enable.dsl = 2

process BIOC_EPIALLELER_LONG_READ_METHYLATION_REPORTING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("epialleleR")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    library(epialleleR)
    
    # Define input file
    input_bam <- "longread.bam"
    
    # Check if input file exists
    if (!file.exists(input_bam)) {
      stop(paste("Required input file missing:", input_bam))
    }
    
    # 1. Preprocess the long-read BAM file with specific mapping, base quality, and probability thresholds
    message("Preprocessing long-read BAM file...")
    longread.data <- preprocessBam(
      input_bam,
      min.mapq=30, min.baseq=20, min.prob=178
    )
    
    # 2. Generate conventional cytosine reports
    message("Generating conventional cytosine report...")
    report <- generateCytosineReport(longread.data, threshold.reads=FALSE)
    
    # Save the output to a CSV file
    output_file <- "cytosine_report.csv"
    message(paste("Saving report to", output_file))
    write.csv(report, file=output_file, row.names=FALSE)
    
    # Save the preprocessed data object as RDS for downstream analysis if needed
    saveRDS(longread.data, file="preprocessed_longread_data.rds")
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_EPIALLELER_LONG_READ_METHYLATION_REPORTING":',
        paste0('    epialleleR: ', as.character(packageVersion('epialleleR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_long_read_methylation_reporting.csv versions.yml
    """
}

workflow BIOC_EPIALLELER_LONG_READ_METHYLATION_REPORTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ longread.bam ] ]

    main:
    BIOC_EPIALLELER_LONG_READ_METHYLATION_REPORTING(ch_input)

    emit:
    tables   = BIOC_EPIALLELER_LONG_READ_METHYLATION_REPORTING.out.tables
    plots    = BIOC_EPIALLELER_LONG_READ_METHYLATION_REPORTING.out.plots
    objects  = BIOC_EPIALLELER_LONG_READ_METHYLATION_REPORTING.out.objects
    versions = BIOC_EPIALLELER_LONG_READ_METHYLATION_REPORTING.out.versions
}
