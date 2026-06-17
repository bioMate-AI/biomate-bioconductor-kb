#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: quantiseqr — deconvolution_from_matrix
// Perform immune cell deconvolution on a gene expression matrix and plot the resulting cell fractions.
// Input: expression_matrix.txt
// Container: quay.io/biocontainers/bioconductor-quantiseqr:1.18.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ggplot2, quantiseqr
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run the deconvolution using run_quantiseq
//  * 2. [Visualization & Output] Visualize the estimated cell fractions as a stacked barplot using quantiplot

nextflow.enable.dsl = 2

process BIOC_QUANTISEQR_DECONVOLUTION_FROM_MATRIX {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("quantiseqr", "ggplot2")
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
    library(quantiseqr)
    library(ggplot2)
    
    # Verify input file existence
    input_file <- "expression_matrix.txt"
    if (!file.exists(input_file)) {
      stop(paste("Error: Required input file '", input_file, "' not found in the working directory.", sep = ""))
    }
    
    # Read the expression matrix (TPM values, HGNC symbols as row names, samples as columns)
    expr_mat <- read.table(input_file, header = TRUE, sep = "\t", row.names = 1, check.names = FALSE)
    expr_mat <- as.matrix(expr_mat)
    
    # Perform immune cell deconvolution using the exact documented function call
    ti_racle <- quantiseqr::run_quantiseq(
      expression_data = expr_mat,
      signature_matrix = "TIL10",
      is_arraydata = FALSE,
      is_tumordata = TRUE,
      scale_mRNA = TRUE
    )
    
    # Save the estimated cell fractions as a CSV table
    write.csv(ti_racle, "deconvolution_results.csv", row.names = TRUE)
    
    # Save the results as an RDS object for downstream R analyses
    saveRDS(ti_racle, "deconvolution_results.rds")
    
    # Visualize the estimated cell fractions as a stacked barplot and save to PDF
    pdf("deconvolution_plot.pdf", width = 10, height = 6)
    p <- quantiplot(ti_racle)
    print(p)
    dev.off()

    writeLines(c(
        '"BIOC_QUANTISEQR_DECONVOLUTION_FROM_MATRIX":',
        paste0('    quantiseqr: ', as.character(packageVersion('quantiseqr')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_deconvolution_from_matrix.csv versions.yml
    """
}

workflow BIOC_QUANTISEQR_DECONVOLUTION_FROM_MATRIX_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.txt ] ]

    main:
    BIOC_QUANTISEQR_DECONVOLUTION_FROM_MATRIX(ch_input)

    emit:
    tables   = BIOC_QUANTISEQR_DECONVOLUTION_FROM_MATRIX.out.tables
    plots    = BIOC_QUANTISEQR_DECONVOLUTION_FROM_MATRIX.out.plots
    objects  = BIOC_QUANTISEQR_DECONVOLUTION_FROM_MATRIX.out.objects
    versions = BIOC_QUANTISEQR_DECONVOLUTION_FROM_MATRIX.out.versions
}
