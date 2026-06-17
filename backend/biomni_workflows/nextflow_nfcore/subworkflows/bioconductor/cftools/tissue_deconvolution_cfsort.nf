#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cfTools — tissue_deconvolution_cfsort
// Estimate fractions of cfDNA fragments derived from 29 major human tissues using a supervised deep learning model.
// Input: cfsort_reads.txt.gz
// Container: quay.io/biocontainers/bioconductor-cftools:1.10.0--r45ha27e39d_0
// R packages: cfTools
// Bioconductor: 3.20 | R: 4.4
// Requires: cfTools
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run cfSort to estimate fractions across 29 tissue types

nextflow.enable.dsl = 2

process BIOC_CFTOOLS_TISSUE_DECONVOLUTION_CFSORT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("cfTools")
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
    library(cfTools)
    
    # Define the input file path from the working directory
    fragMethInfo <- "cfsort_reads.txt.gz"
    
    # Check if the input file exists
    if (!file.exists(fragMethInfo)) {
      stop(paste("Required input file missing:", fragMethInfo))
    }
    
    # Display the first few rows of the input file as shown in the documentation
    cat("--- Preview of Input Data ---\n")
    print(head(read.csv(fragMethInfo, header=TRUE, sep="\t", 
                        colClasses = "character"), 4))
    cat("\n")
    
    # Run cfSort to estimate fractions across 29 tissue types
    cat("--- Running cfSort Tissue Deconvolution ---\n")
    tissueFraction2 <- cfSort(fragMethInfo, id="demo")
    
    # Display the resulting tissue fractions
    cat("\n--- Estimated Tissue Fractions ---\n")
    print(tissueFraction2)
    
    # Write the meaningful results to output files
    cat("\n--- Saving Results ---\n")
    write.csv(tissueFraction2, "cfsort_tissue_fractions.csv", row.names = FALSE)
    saveRDS(tissueFraction2, "cfsort_tissue_fractions.rds")
    cat("Results successfully saved to 'cfsort_tissue_fractions.csv' and 'cfsort_tissue_fractions.rds'.\n")

    writeLines(c(
        '"BIOC_CFTOOLS_TISSUE_DECONVOLUTION_CFSORT":',
        paste0('    cfTools: ', as.character(packageVersion('cfTools')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tissue_deconvolution_cfsort.csv versions.yml
    """
}

workflow BIOC_CFTOOLS_TISSUE_DECONVOLUTION_CFSORT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ cfsort_reads.txt.gz ] ]

    main:
    BIOC_CFTOOLS_TISSUE_DECONVOLUTION_CFSORT(ch_input)

    emit:
    tables   = BIOC_CFTOOLS_TISSUE_DECONVOLUTION_CFSORT.out.tables
    plots    = BIOC_CFTOOLS_TISSUE_DECONVOLUTION_CFSORT.out.plots
    objects  = BIOC_CFTOOLS_TISSUE_DECONVOLUTION_CFSORT.out.objects
    versions = BIOC_CFTOOLS_TISSUE_DECONVOLUTION_CFSORT.out.versions
}
