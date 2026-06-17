#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scBFA — binary_factor_analysis
// Perform dimensionality reduction on scRNA-seq gene detection patterns using Binary Factor Analysis (BFA).
// Input: exprdata
// Container: quay.io/biocontainers/bioconductor-scbfa:1.24.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, scBFA
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Construct a SingleCellExperiment object from the raw count matrix
//  * 2. [Core Analysis] Run the scBFA model to compute the low-dimensional embedding
//  * 3. [Visualization & Output] Extract the embedding matrix (ZZ) for downstream visualization or analysis

nextflow.enable.dsl = 2

process BIOC_SCBFA_BINARY_FACTOR_ANALYSIS {
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
    .bm_deps <- c("scBFA")
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
    library(scBFA)
    
    # 1. Read the user input file 'exprdata' from the working directory
    # We check for common formats: RDS, CSV, or a plain text file.
    if (file.exists("exprdata.rds")) {
      exprdata <- readRDS("exprdata.rds")
    } else if (file.exists("exprdata.csv")) {
      exprdata <- read.csv("exprdata.csv", row.names = 1, check.names = FALSE)
    } else if (file.exists("exprdata")) {
      exprdata <- read.table("exprdata", header = TRUE, row.names = 1, check.names = FALSE)
    } else {
      stop("Error: Required input file 'exprdata' (or exprdata.csv/rds) not found in the working directory.")
    }
    
    # Ensure exprdata is in matrix format
    exprdata <- as.matrix(exprdata)
    
    # 2. Construct a SingleCellExperiment object from the raw count matrix
    sce <- SingleCellExperiment(assay = list(counts = exprdata))
    
    # 3. Run the scBFA model to compute the low-dimensional embedding
    bfa_model = scBFA(scData = sce, numFactors = 2) 
    
    # 4. Extract the embedding matrix (ZZ) for downstream visualization or analysis
    df = as.data.frame(bfa_model\$ZZ)
    
    # 5. Write named output files for the meaningful results
    # Save the low-dimensional embeddings as a CSV table
    write.csv(df, file = "bfa_embeddings.csv", row.names = TRUE)
    
    # Save the full scBFA model object as an RDS file
    saveRDS(bfa_model, file = "bfa_model.rds")
    
    # Save the SingleCellExperiment object as an RDS file
    saveRDS(sce, file = "sce_bfa.rds")
    
    cat("Workflow completed successfully. Outputs saved: 'bfa_embeddings.csv', 'bfa_model.rds', 'sce_bfa.rds'.\n")

    writeLines(c(
        '"BIOC_SCBFA_BINARY_FACTOR_ANALYSIS":',
        paste0('    scBFA: ', as.character(packageVersion('scBFA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_binary_factor_analysis.csv versions.yml
    """
}

workflow BIOC_SCBFA_BINARY_FACTOR_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ exprdata ] ]

    main:
    BIOC_SCBFA_BINARY_FACTOR_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SCBFA_BINARY_FACTOR_ANALYSIS.out.tables
    plots    = BIOC_SCBFA_BINARY_FACTOR_ANALYSIS.out.plots
    objects  = BIOC_SCBFA_BINARY_FACTOR_ANALYSIS.out.objects
    versions = BIOC_SCBFA_BINARY_FACTOR_ANALYSIS.out.versions
}
