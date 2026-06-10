#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Rfastp — fastq_concatenation
// Concatenate multiple split FASTQ files into a single file, either as part of the QC pipeline or as a standalone operation.
// Input: pe001_read1, pe002_read1, pe003_read1, pe004_read1, pe001_read2, pe002_read2, pe003_read2, pe004_read2
// Container: quay.io/biocontainers/bioconductor-rfastp:1.20.1--r45ha27e39d_0
// R packages: Rfastp, ggplot2
// Bioconductor: 3.20 | R: 4.4
// Requires: Rfastp, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Pass a vector of input files to rfastp to concatenate and run QC
//  * 2. [Visualization & Output] Use catfastq to concatenate multiple files into a single output file without running QC

nextflow.enable.dsl = 2

process BIOC_RFASTP_FASTQ_CONCATENATION {
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
    
    # Load required libraries
    library(Rfastp)
    library(ggplot2)
    
    # Define input files from the working directory as specified by the user
    pe001_read1 <- "pe001_read1"
    pe002_read1 <- "pe002_read1"
    pe003_read1 <- "pe003_read1"
    pe004_read1 <- "pe004_read1"
    
    pe001_read2 <- "pe001_read2"
    pe002_read2 <- "pe002_read2"
    pe003_read2 <- "pe003_read2"
    pe004_read2 <- "pe004_read2"
    
    # Define output prefix for the results
    outputPrefix <- "rfastp_output"
    
    # Stage 1: Pass a vector of input files to rfastp to concatenate and run QC
    inputfiles <- c(pe001_read1, pe002_read1, pe003_read1, pe004_read1)
    cat_rjson_report <- rfastp(read1 = inputfiles, 
        outputFastq = paste0(outputPrefix, "_merged1"))
    
    # Stage 2: Use catfastq to concatenate multiple files into a single output file without running QC
    inputR2files <- c(pe001_read2, pe002_read2, pe003_read2, pe004_read2)
    catfastq(output = paste0(outputPrefix,"_merged2_R2.fastq.gz"), 
        inputFiles = inputR2files)
    
    # Save meaningful results to disk
    
    # 1. Save the complete Rfastp report object as an RDS file
    saveRDS(cat_rjson_report, file = paste0(outputPrefix, "_report.rds"))
    
    # 2. Generate and save the QC Summary Table
    tryCatch({
        dfsummary <- qcSummary(cat_rjson_report)
        write.csv(dfsummary, file = paste0(outputPrefix, "_qc_summary.csv"), row.names = FALSE)
    }, error = function(e) {
        warning("Could not generate or save QC summary: ", e\$message)
    })
    
    # 3. Generate and save the Trimming Summary Table
    tryCatch({
        dfTrim <- trimSummary(cat_rjson_report)
        write.csv(dfTrim, file = paste0(outputPrefix, "_trim_summary.csv"), row.names = FALSE)
    }, error = function(e) {
        warning("Could not generate or save trimming summary: ", e\$message)
    })
    
    # 4. Generate and save Base Quality Plot
    tryCatch({
        p1 <- curvePlot(cat_rjson_report)
        ggsave(filename = paste0(outputPrefix, "_base_quality_plot.pdf"), plot = p1, width = 8, height = 6)
    }, error = function(e) {
        warning("Could not generate or save base quality plot: ", e\$message)
    })
    
    # 5. Generate and save GC Content Plot
    tryCatch({
        p2 <- curvePlot(cat_rjson_report, curve = "content_curves")
        ggsave(filename = paste0(outputPrefix, "_gc_content_plot.pdf"), plot = p2, width = 8, height = 6)
    }, error = function(e) {
        warning("Could not generate or save GC content plot: ", e\$message)
    })

    writeLines(c(
        '"BIOC_RFASTP_FASTQ_CONCATENATION":',
        paste0('    Rfastp: ', as.character(packageVersion('Rfastp')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fastq_concatenation.csv versions.yml
    """
}

workflow BIOC_RFASTP_FASTQ_CONCATENATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pe001_read1, pe002_read1, pe003_read1, pe004_read1, pe001_read2, pe002_read2, pe003_read2, pe004_read2 ] ]

    main:
    BIOC_RFASTP_FASTQ_CONCATENATION(ch_input)

    emit:
    tables   = BIOC_RFASTP_FASTQ_CONCATENATION.out.tables
    plots    = BIOC_RFASTP_FASTQ_CONCATENATION.out.plots
    objects  = BIOC_RFASTP_FASTQ_CONCATENATION.out.objects
    versions = BIOC_RFASTP_FASTQ_CONCATENATION.out.versions
}
