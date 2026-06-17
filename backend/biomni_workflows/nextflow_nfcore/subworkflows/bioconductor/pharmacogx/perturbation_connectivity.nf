#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: PharmacoGx — perturbation_connectivity
// Query a perturbation dataset with a gene expression signature to identify drugs with similar or opposite effects.
// Input: CMAPsmall, HDAC_genes
// Container: quay.io/biocontainers/bioconductor-pharmacogx:3.14.0--r45ha27e39d_0
// R packages: PharmacoGx, pander
// Bioconductor: 3.20 | R: 4.4
// Requires: PharmacoGx, pander
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Compute drug perturbation signatures using
//  * 2. [Core Analysis] Calculate connectivity scores between the drug signatures
//  * 3. [Core Analysis] Rank and format the results

nextflow.enable.dsl = 2

process BIOC_PHARMACOGX_PERTURBATION_CONNECTIVITY {
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
    .bm_deps <- c("PharmacoGx", "pander")
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
    library(PharmacoGx)
    library(pander)
    
    # Read user input files from the working directory
    if (file.exists("CMAPsmall")) {
      CMAPsmall <- readRDS("CMAPsmall")
    } else if (file.exists("CMAPsmall.rds")) {
      CMAPsmall <- readRDS("CMAPsmall.rds")
    } else {
      stop("Error: CMAPsmall file not found in the working directory.")
    }
    
    if (file.exists("HDAC_genes")) {
      HDAC_genes <- readRDS("HDAC_genes")
    } else if (file.exists("HDAC_genes.rds")) {
      HDAC_genes <- readRDS("HDAC_genes.rds")
    } else if (file.exists("HDAC_genes.csv")) {
      HDAC_genes <- read.csv("HDAC_genes.csv", stringsAsFactors = FALSE, row.names = 1)
    } else {
      stop("Error: HDAC_genes file not found in the working directory.")
    }
    
    # Ensure HDAC_genes has gene names as rownames and is a 1-column data.frame
    if (ncol(HDAC_genes) >= 2) {
      rownames(HDAC_genes) <- HDAC_genes[, 1]
      HDAC_genes <- HDAC_genes[, 2, drop = FALSE]
    } else {
      HDAC_genes <- HDAC_genes[, 1, drop = FALSE]
    }
    
    # --- Compute drug perturbation signatures using ---
    drug.perturbation <- drugPerturbationSig(CMAPsmall, mDataType="rna", verbose=FALSE)
    
    # Save intermediate drug perturbation signature
    saveRDS(drug.perturbation, "drug_perturbation_sig.rds")
    
    # --- Calculate connectivity scores between the drug signatures ---
    y_vec <- setNames(as.numeric(HDAC_genes[, 1]), rownames(HDAC_genes))
    res <- apply(drug.perturbation[, , "tstat", drop=FALSE], 2, function(x, y_ref, gene_names){ 
      x_vec <- setNames(as.numeric(x), gene_names)
      return(connectivityScore(x=x_vec, y=y_ref, method="fgsea", nperm=100)) 
    }, y_ref=y_vec, gene_names=dimnames(drug.perturbation)[[1]])
    
    # --- Rank and format the results ---
    rownames(res) <- c("Connectivity", "P Value")
    res <- t(res)
    res <- res[order(res[,1], decreasing=TRUE),]
    
    # Print table to console/output
    pander::pandoc.table(res, caption='Connectivity Score results for HDAC inhibitor gene signature.', style = 'rmarkdown')
    
    # Write outputs to files
    write.csv(res, "connectivity_results.csv", row.names=TRUE)
    saveRDS(res, "connectivity_results.rds")

    writeLines(c(
        '"BIOC_PHARMACOGX_PERTURBATION_CONNECTIVITY":',
        paste0('    PharmacoGx: ', as.character(packageVersion('PharmacoGx')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_perturbation_connectivity.csv versions.yml
    """
}

workflow BIOC_PHARMACOGX_PERTURBATION_CONNECTIVITY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ CMAPsmall, HDAC_genes ] ]

    main:
    BIOC_PHARMACOGX_PERTURBATION_CONNECTIVITY(ch_input)

    emit:
    tables   = BIOC_PHARMACOGX_PERTURBATION_CONNECTIVITY.out.tables
    plots    = BIOC_PHARMACOGX_PERTURBATION_CONNECTIVITY.out.plots
    objects  = BIOC_PHARMACOGX_PERTURBATION_CONNECTIVITY.out.objects
    versions = BIOC_PHARMACOGX_PERTURBATION_CONNECTIVITY.out.versions
}
