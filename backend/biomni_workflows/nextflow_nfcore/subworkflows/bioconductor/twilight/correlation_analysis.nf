#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: twilight — correlation_analysis
// Identify genes whose expression levels correlate with a continuous clinical parameter.
// Input: expression_matrix.csv, clinical_parameter.csv
// Container: quay.io/biocontainers/bioconductor-twilight:1.86.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: twilight
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Extract the continuous clinical parameter vector
//  * 2. [Core Analysis] Compute correlation-based p-values and q-values using twilight.pval with Spearman or Pearson method
//  * 3. [Visualization & Output] Plot the correlation scores

nextflow.enable.dsl = 2

process BIOC_TWILIGHT_CORRELATION_ANALYSIS {
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
    .bm_deps <- c("twilight")
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
    library(twilight)
    
    # 1. Read the user input files
    # Read expression matrix (genes as rows, samples as columns)
    golubNorm <- as.matrix(read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE))
    
    # Read clinical parameter
    clinical_df <- read.csv("clinical_parameter.csv", check.names = FALSE)
    
    # Extract the continuous clinical parameter vector and align with expression matrix columns
    if (ncol(clinical_df) >= 2) {
      # Try to match by sample IDs if the first column contains them
      if (any(clinical_df[[1]] %in% colnames(golubNorm))) {
        rownames(clinical_df) <- clinical_df[[1]]
        clinical_df <- clinical_df[colnames(golubNorm), , drop = FALSE]
      }
      # Find the first numeric column
      numeric_cols <- sapply(clinical_df, is.numeric)
      if (any(numeric_cols)) {
        gene <- as.numeric(clinical_df[[which(numeric_cols)[1]]])
      } else {
        gene <- as.numeric(clinical_df[[2]])
      }
    } else {
      gene <- as.numeric(clinical_df[[1]])
    }
    
    # Sanity check to ensure lengths match
    if (length(gene) != ncol(golubNorm)) {
      stop("The length of the clinical parameter vector does not match the number of samples in the expression matrix.")
    }
    
    # 2. Compute correlation-based p-values and q-values using twilight.pval
    # Keep the documented function call and its argument names EXACTLY as shown:
    corr <- twilight.pval(golubNorm,gene,method="spearman",quant.ci=0.99,B=100)
    
    # 3. Plot the correlation scores and save to PDF
    pdf("correlation_scores_plot.pdf", width = 7, height = 7)
    plot(corr,which="scores",grayscale=F,legend=F)
    dev.off()
    
    # 4. Write named output files for the meaningful results
    # Save the results table
    write.csv(corr\$result, "correlation_analysis_results.csv", row.names = TRUE)
    
    # Save the twilight object as RDS
    saveRDS(corr, "correlation_analysis_object.rds")

    writeLines(c(
        '"BIOC_TWILIGHT_CORRELATION_ANALYSIS":',
        paste0('    twilight: ', as.character(packageVersion('twilight')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_correlation_analysis.csv versions.yml
    """
}

workflow BIOC_TWILIGHT_CORRELATION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv, clinical_parameter.csv ] ]

    main:
    BIOC_TWILIGHT_CORRELATION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_TWILIGHT_CORRELATION_ANALYSIS.out.tables
    plots    = BIOC_TWILIGHT_CORRELATION_ANALYSIS.out.plots
    objects  = BIOC_TWILIGHT_CORRELATION_ANALYSIS.out.objects
    versions = BIOC_TWILIGHT_CORRELATION_ANALYSIS.out.versions
}
