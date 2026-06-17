#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: pcaMethods — pca_and_imputation
// Perform PCA on a matrix containing missing values and impute the missing values to obtain a complete dataset.
// Input: metaboliteData
// Container: quay.io/biocontainers/bioconductor-pcamethods:2.2.0--r45ha27e39d_0
// R packages: Biobase, ggplot2, pcaMethods
// Bioconductor: 3.20 | R: 4.4
// Requires: pcaMethods
// Visualizations: PCA plot
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run PCA using a method that handles missing values (e.g., PPCA)
//  * 2. [Core Analysis] Impute missing values using completeObs

nextflow.enable.dsl = 2

process BIOC_PCAMETHODS_PCA_AND_IMPUTATION {
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
    .bm_deps <- c("Biobase", "ggplot2", "pcaMethods")
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
    library(pcaMethods)
    
    # Locate and read the user input file
    # The user input is specified as 'metaboliteData' (matrix containing missing values represented as NA)
    input_file <- "metaboliteData.csv"
    if (!file.exists(input_file)) {
      if (file.exists("metaboliteData")) {
        input_file <- "metaboliteData"
      } else if (file.exists("metaboliteData.txt")) {
        input_file <- "metaboliteData.txt"
      } else {
        stop("Error: Input file 'metaboliteData' (CSV or TXT format) not found in the working directory.")
      }
    }
    
    # Read the matrix data
    mD_df <- read.csv(input_file, row.names = 1, check.names = FALSE)
    mD <- as.matrix(mD_df)
    
    # 1. Run PCA using a method that handles missing values (PPCA)
    # Keep function call and arguments exactly as documented
    pc <- pca(mD, nPcs=3, method="ppca")
    
    # 2. Impute missing values using completeObs
    # Keep function call and arguments exactly as documented
    imputed <- completeObs(pc)
    
    # Write named output files for the meaningful results
    write.csv(imputed, "imputed_metaboliteData.csv", row.names = TRUE)
    write.csv(scores(pc), "pca_scores.csv", row.names = TRUE)
    write.csv(loadings(pc), "pca_loadings.csv", row.names = TRUE)
    saveRDS(pc, "pca_model.rds")
    
    # Generate diagnostic plots
    pdf("pca_plots.pdf", width = 7, height = 7)
    plotPcs(pc, pc=1:3, type="score")
    dev.off()

    writeLines(c(
        '"BIOC_PCAMETHODS_PCA_AND_IMPUTATION":',
        paste0('    pcaMethods: ', as.character(packageVersion('pcaMethods')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pca_and_imputation.csv versions.yml
    """
}

workflow BIOC_PCAMETHODS_PCA_AND_IMPUTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ metaboliteData ] ]

    main:
    BIOC_PCAMETHODS_PCA_AND_IMPUTATION(ch_input)

    emit:
    tables   = BIOC_PCAMETHODS_PCA_AND_IMPUTATION.out.tables
    plots    = BIOC_PCAMETHODS_PCA_AND_IMPUTATION.out.plots
    objects  = BIOC_PCAMETHODS_PCA_AND_IMPUTATION.out.objects
    versions = BIOC_PCAMETHODS_PCA_AND_IMPUTATION.out.versions
}
