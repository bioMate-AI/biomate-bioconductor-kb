#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mCSEA — methylation_expression_integration
// Integrate DMR results with gene expression data to identify significant correlations between regional methylation and nearby gene expression.
// Input: mCSEATest_results.rds, gene_expression.matrix
// Container: quay.io/biocontainers/bioconductor-mcsea:1.30.1--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: mCSEA
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] GSEA results list from mCSEATest
//  * 2. [Core Analysis] Matrix of gene expression values (genes as rows, samples

nextflow.enable.dsl = 2

process BIOC_MCSEA_METHYLATION_EXPRESSION_INTEGRATION {
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
    .bm_deps <- c("mCSEA")
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
    
    # Load required library
    library(mCSEA)
    
    # Read user input files from the working directory
    # --- GSEA results list from mCSEATest ---
    myResults <- readRDS("mCSEATest_results.rds")
    
    # --- Matrix of gene expression values (genes as rows, samples ---
    expr_df <- read.table("gene_expression.matrix", header = TRUE, row.names = 1, sep = "", check.names = FALSE)
    exprTest <- as.matrix(expr_df)
    
    # Run integration and correlation analysis using mCSEAIntegrate()
    # This function automatically generates correlation plots for significant results
    # and saves them in the current working directory.
    resultsInt <- mCSEAIntegrate(myResults, exprTest, "promoters", "ENSEMBL")
    
    # Write meaningful output files
    write.csv(resultsInt, "integration_results.csv", row.names = FALSE)
    saveRDS(resultsInt, "integration_results.rds")

    writeLines(c(
        '"BIOC_MCSEA_METHYLATION_EXPRESSION_INTEGRATION":',
        paste0('    mCSEA: ', as.character(packageVersion('mCSEA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_methylation_expression_integration.csv versions.yml
    """
}

workflow BIOC_MCSEA_METHYLATION_EXPRESSION_INTEGRATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ mCSEATest_results.rds, gene_expression.matrix ] ]

    main:
    BIOC_MCSEA_METHYLATION_EXPRESSION_INTEGRATION(ch_input)

    emit:
    tables   = BIOC_MCSEA_METHYLATION_EXPRESSION_INTEGRATION.out.tables
    plots    = BIOC_MCSEA_METHYLATION_EXPRESSION_INTEGRATION.out.plots
    objects  = BIOC_MCSEA_METHYLATION_EXPRESSION_INTEGRATION.out.objects
    versions = BIOC_MCSEA_METHYLATION_EXPRESSION_INTEGRATION.out.versions
}
