#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: multiscan — estimate_gene_expression_multiscan
// Estimate gene expressions from multiple laser scans of a single microarray and perform model diagnostics.
// Input: intensity_data.csv
// Container: quay.io/biocontainers/bioconductor-multiscan:1.70.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: multiscan
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the raw intensity data
//  * 2. [Core Analysis] Fit the non-linear functional regression model using multiscan
//  * 3. [Core Analysis] Inspect the fitted model object
//  * 4. [Core Analysis] Extract the estimated gene expressions
//  * 5. [Visualization & Output] Plot the fitted model and diagnostic residuals

nextflow.enable.dsl = 2

process BIOC_MULTISCAN_ESTIMATE_GENE_EXPRESSION_MULTISCAN {
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
    .bm_deps <- c("multiscan")
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
    library(multiscan)
    
    # 1. Load the raw intensity data
    # Read the user input file 'intensity_data.csv'
    raw_data <- read.csv("intensity_data.csv", header = TRUE, check.names = FALSE)
    
    # Process the data to ensure it is a numeric matrix/data frame
    # If the first column is non-numeric (e.g., probe IDs), set them as row names
    if (!is.numeric(raw_data[[1]])) {
      row_names <- raw_data[[1]]
      murine <- as.matrix(raw_data[, -1, drop = FALSE])
      rownames(murine) <- row_names
    } else {
      murine <- as.matrix(raw_data)
    }
    
    # 2. Fit the non-linear functional regression model using multiscan
    fit<-multiscan(murine)
    
    # 3. Inspect the fitted model object
    fit
    str(fit)
    
    # 4. Extract the estimated gene expressions
    gene.exprs<-fit\$mu
    
    # Save the estimated gene expressions to a CSV file
    probe_ids <- rownames(murine)
    if (is.null(probe_ids)) {
      probe_ids <- seq_len(nrow(murine))
    }
    expression_df <- data.frame(ProbeID = probe_ids, EstimatedExpression = gene.exprs)
    write.csv(expression_df, "gene_expression_estimates.csv", row.names = FALSE)
    
    # Save the fitted model object as an RDS file
    saveRDS(fit, "multiscan_fit.rds")
    
    # 5. Plot the fitted model and diagnostic residuals
    # Save the fitted model plot
    pdf("multiscan_fit_plot.pdf", width = 7, height = 7)
    plot(fit)
    dev.off()
    
    # Save the diagnostic residuals plot
    pdf("multiscan_diagnostics_plot.pdf", width = 8, height = 8)
    op<-par(mfrow=c(2,2))
    plot(fit,residual=TRUE)
    par(op)
    dev.off()

    writeLines(c(
        '"BIOC_MULTISCAN_ESTIMATE_GENE_EXPRESSION_MULTISCAN":',
        paste0('    multiscan: ', as.character(packageVersion('multiscan')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_estimate_gene_expression_multiscan.csv versions.yml
    """
}

workflow BIOC_MULTISCAN_ESTIMATE_GENE_EXPRESSION_MULTISCAN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ intensity_data.csv ] ]

    main:
    BIOC_MULTISCAN_ESTIMATE_GENE_EXPRESSION_MULTISCAN(ch_input)

    emit:
    tables   = BIOC_MULTISCAN_ESTIMATE_GENE_EXPRESSION_MULTISCAN.out.tables
    plots    = BIOC_MULTISCAN_ESTIMATE_GENE_EXPRESSION_MULTISCAN.out.plots
    objects  = BIOC_MULTISCAN_ESTIMATE_GENE_EXPRESSION_MULTISCAN.out.objects
    versions = BIOC_MULTISCAN_ESTIMATE_GENE_EXPRESSION_MULTISCAN.out.versions
}
