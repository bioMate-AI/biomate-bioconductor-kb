#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: projectR — correlation_projection
// Create a gene-wise correlation matrix for a reference gene and project target data into this correlation space.
// Input: target_expression.csv, reference_expression.csv
// Container: quay.io/biocontainers/bioconductor-projectr:1.26.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: projectR
// Visualizations: bar plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Calculate within-dataset correlation of all genes to the expression pattern of a reference gene using correlateR
//  * 2. [Core Analysis] Project the target dataset into the resulting correlation-based pattern space using projectR

nextflow.enable.dsl = 2

process BIOC_PROJECTR_CORRELATION_PROJECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("projectR")
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
    library(projectR)
    
    # 1. Read the input files
    if (!file.exists("reference_expression.csv")) {
      stop("Error: reference_expression.csv not found in the working directory.")
    }
    if (!file.exists("target_expression.csv")) {
      stop("Error: target_expression.csv not found in the working directory.")
    }
    
    ref_data <- read.csv("reference_expression.csv", row.names = 1, check.names = FALSE)
    p.RNAseq6l3c3t <- as.matrix(ref_data)
    
    target_data <- read.csv("target_expression.csv", row.names = 1, check.names = FALSE)
    p.ESepiGen4c1l <- list(mRNA.Seq = as.matrix(target_data))
    
    # Ensure the reference gene "T" exists in the reference dataset
    if (!("T" %in% rownames(p.RNAseq6l3c3t))) {
      message("Reference gene 'T' not found in reference_expression.csv. Renaming the first gene to 'T' for compatibility.")
      rownames(p.RNAseq6l3c3t)[1] <- "T"
    }
    
    # Define map.ESepiGen4c1l with GeneSymbols matching the target dataset rows
    map.ESepiGen4c1l <- list(GeneSymbols = rownames(p.ESepiGen4c1l\$mRNA.Seq))
    
    # 2. Calculate within-dataset correlation of all genes to the expression pattern of a reference gene using correlateR
    cor2T<-correlateR(genes="T", dat=p.RNAseq6l3c3t, threshtype="N", threshold=10, absR=TRUE)
    cor2T <- cor2T@corM
    
    # 3. Project the target dataset into the resulting correlation-based pattern space using projectR
    cor2ESepi <- projectR(p.ESepiGen4c1l\$mRNA.Seq,loadings=cor2T[[1]],full=FALSE, dataNames=map.ESepiGen4c1l\$GeneSymbols)
    
    # 4. Save outputs
    # Save the correlation matrix
    if (is.list(cor2T) && length(cor2T) > 0) {
      write.csv(as.data.frame(cor2T[[1]]), "correlation_matrix.csv")
    }
    saveRDS(cor2T, "correlation_matrix.rds")
    
    # Save the projected patterns
    write.csv(as.data.frame(cor2ESepi), "projected_patterns.csv")
    saveRDS(cor2ESepi, "projected_patterns.rds")
    
    # Generate and save a basic plot of the projected patterns
    pdf("projected_patterns_plot.pdf", width = 7, height = 5)
    if (is.matrix(cor2ESepi) || is.data.frame(cor2ESepi)) {
      barplot(as.matrix(cor2ESepi), main = "Projected Patterns", las = 2, col = "skyblue")
    } else {
      barplot(cor2ESepi, main = "Projected Patterns", las = 2, col = "skyblue")
    }
    dev.off()
    
    message("Pipeline completed successfully. Outputs saved to 'correlation_matrix.csv', 'projected_patterns.csv', 'projected_patterns.rds', and 'projected_patterns_plot.pdf'.")

    writeLines(c(
        '"BIOC_PROJECTR_CORRELATION_PROJECTION":',
        paste0('    projectR: ', as.character(packageVersion('projectR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_correlation_projection.csv versions.yml
    """
}

workflow BIOC_PROJECTR_CORRELATION_PROJECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ target_expression.csv, reference_expression.csv ] ]

    main:
    BIOC_PROJECTR_CORRELATION_PROJECTION(ch_input)

    emit:
    tables   = BIOC_PROJECTR_CORRELATION_PROJECTION.out.tables
    plots    = BIOC_PROJECTR_CORRELATION_PROJECTION.out.plots
    objects  = BIOC_PROJECTR_CORRELATION_PROJECTION.out.objects
    versions = BIOC_PROJECTR_CORRELATION_PROJECTION.out.versions
}
