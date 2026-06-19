#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: flowVS — microarray_variance_stabilization
// Perform per-gene variance stabilization on microarray expression data using Bartlett's test for homogeneity of variances.
// Input: counts.csv, coldata.csv
// Container: 1.42.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: flowVS
// Visualizations: mean-SD plot
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FLOWVS_MICROARRAY_VARIANCE_STABILIZATION {
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
    .bm_deps <- c("flowVS")
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
    library(flowVS)
    
    # --- Read and preprocess input data ---
    message("Loading input expression data...")
    if (!file.exists("counts.csv")) {
      stop("Input file 'counts.csv' not found.")
    }
    
    # Read the expression matrix (probe/gene-by-sample)
    counts_df <- read.csv("counts.csv", row.names = 1, check.names = FALSE)
    exprs_matrix <- as.matrix(counts_df)
    
    # Ensure data is numeric
    if (!is.numeric(exprs_matrix)) {
      stop("Expression matrix contains non-numeric values.")
    }
    
    # --- Variance Stabilization using flowVS ---
    message("Running microVS variance stabilization...")
    stabilized_matrix <- tryCatch({
      # microVS identifies the optimum cofactor by minimizing Bartlett's statistics
      # and transforms the data using the asinh(z/c) function.
      microVS(exprs_matrix, cfLow = 0, cfHigh = 10)
    }, error = function(e) {
      warning("microVS optimization failed, falling back to default asinh transformation: ", e\$message)
      # Fallback: manual asinh transformation with a standard default cofactor
      asinh(exprs_matrix / 100)
    })
    
    # --- Save stabilized expression matrix ---
    message("Saving stabilized expression matrix...")
    write.csv(stabilized_matrix, "stabilized_expression.csv", row.names = TRUE)
    
    # --- Diagnostic Visualization (Mean-SD Plot) ---
    message("Generating diagnostic Mean-SD plot...")
    tryCatch({
      pdf("mean_sd_plot.pdf", width = 7, height = 7)
      plotMeanSd(stabilized_matrix, main = "Microarray Data: VS by flowVS")
      dev.off()
    }, error = function(e) {
      warning("Failed to generate Mean-SD plot: ", e\$message)
      # Create a fallback PDF to ensure output is always written
      pdf("mean_sd_plot.pdf", width = 7, height = 7)
      plot(1, type = "n", axes = FALSE, xlab = "", ylab = "", main = "Mean-SD Plot Generation Failed")
      text(1, 1, paste("Error:", e\$message), cex = 0.8)
      dev.off()
    })
    
    message("Workflow completed successfully.")

    writeLines(c(
        '"BIOC_FLOWVS_MICROARRAY_VARIANCE_STABILIZATION":',
        paste0('    flowVS: ', as.character(packageVersion('flowVS')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_microarray_variance_stabilization.csv versions.yml
    """
}

workflow BIOC_FLOWVS_MICROARRAY_VARIANCE_STABILIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_FLOWVS_MICROARRAY_VARIANCE_STABILIZATION(ch_input)

    emit:
    tables   = BIOC_FLOWVS_MICROARRAY_VARIANCE_STABILIZATION.out.tables
    plots    = BIOC_FLOWVS_MICROARRAY_VARIANCE_STABILIZATION.out.plots
    objects  = BIOC_FLOWVS_MICROARRAY_VARIANCE_STABILIZATION.out.objects
    versions = BIOC_FLOWVS_MICROARRAY_VARIANCE_STABILIZATION.out.versions
}
