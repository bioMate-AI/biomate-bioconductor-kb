#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: QUBIC — bicluster_expanding
// Expand existing biclusters to recruit more genes under a specified consistency level.
// Input: expression_matrix.csv, existing_biclusters.rds
// Container: quay.io/biocontainers/bioconductor-qubic:1.38.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: QUBIC
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Read User Inputs
//  * 2. [Core Analysis] Run the QUBIC algorithm with the seedbicluster parameter
//  * 3. [Core Analysis] Write Named Output Files

nextflow.enable.dsl = 2

process BIOC_QUBIC_BICLUSTER_EXPANDING {
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
    .bm_deps <- c("QUBIC")
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
        
        # Load the required QUBIC package
        library(QUBIC)
        
        # --- Read User Inputs ---
        if (!file.exists("expression_matrix.csv")) {
          stop("Error: 'expression_matrix.csv' not found in the working directory.")
        }
        if (!file.exists("existing_biclusters.rds")) {
          stop("Error: 'existing_biclusters.rds' not found in the working directory.")
        }
        
        # Read the gene expression matrix (assuming first column contains gene names)
        ecoli_df <- read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE)
        ecoli <- as.matrix(ecoli_df)
        
        # Read the existing QUBICBiclustResult object
        res <- readRDS("existing_biclusters.rds")
        
        # --- Run the QUBIC algorithm with the seedbicluster parameter ---
        # (This matches the documented vignette code exactly)
        res5 <- qubiclust(x = ecoli, seedbicluster = res, f = 0.25, verbose = FALSE)
        summary(res5)
        
        # --- Write Named Output Files ---
        # Save the complete expanded bicluster result object
        saveRDS(res5, "expanded_biclusters.rds")
        
        # Save the summary text output
        sink("expanded_biclusters_summary.txt")
        summary(res5)
        sink()
        
        # Extract and save basic bicluster metadata (sizes) to a CSV file
        if (res5@Number > 0) {
          bicluster_info <- data.frame(
            Bicluster = paste0("BC_", seq_len(res5@Number)),
            Genes = colSums(res5@RowxNumber),
            Conditions = rowSums(res5@NumberxCol)
          )
          write.csv(bicluster_info, "expanded_biclusters_info.csv", row.names = FALSE)
        }

    writeLines(c(
        '"BIOC_QUBIC_BICLUSTER_EXPANDING":',
        paste0('    QUBIC: ', as.character(packageVersion('QUBIC')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bicluster_expanding.csv versions.yml
    """
}

workflow BIOC_QUBIC_BICLUSTER_EXPANDING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv, existing_biclusters.rds ] ]

    main:
    BIOC_QUBIC_BICLUSTER_EXPANDING(ch_input)

    emit:
    tables   = BIOC_QUBIC_BICLUSTER_EXPANDING.out.tables
    plots    = BIOC_QUBIC_BICLUSTER_EXPANDING.out.plots
    objects  = BIOC_QUBIC_BICLUSTER_EXPANDING.out.objects
    versions = BIOC_QUBIC_BICLUSTER_EXPANDING.out.versions
}
