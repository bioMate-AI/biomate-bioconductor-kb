#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RUVnormalize — iterative_ruv
// Iteratively estimate and remove unwanted variation and the factor of interest using sparse dictionary learning.
// Input: expression_matrix.csv, negative_controls.txt, replicates_mapping.csv
// Container: quay.io/biocontainers/bioconductor-ruvnormalize:1.44.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: RUVnormalize, spams
// Visualizations: PCA plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read user input files
//  * 2. [Input & Preparation] Define the sparse dictionary learning parameters and run
//  * 3. [Input & Preparation] Define parameters and run iterative RUV (SVD-based)
//  * 4. [Input & Preparation] Generate diagnostic PCA plots

nextflow.enable.dsl = 2

process BIOC_RUVNORMALIZE_ITERATIVE_RUV {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
        
        # Load required libraries
        library(RUVnormalize)
        library(spams)
        
        # --- Read user input files ---
        # Read expression matrix (samples as rows, genes as columns)
        Y <- as.matrix(read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE))
        
        # Center the gene expression matrix
        Y <- scale(Y, scale = FALSE)
        
        # Read negative control genes
        cIdx_raw <- readLines("negative_controls.txt")
        cIdx_raw <- cIdx_raw[cIdx_raw != ""]
        if (all(grepl("^[0-9]+\$", cIdx_raw))) {
          cIdx <- as.integer(cIdx_raw)
        } else {
          cIdx <- which(colnames(Y) %in% cIdx_raw)
        }
        
        # Read replicates mapping matrix
        scIdx <- as.matrix(read.csv("replicates_mapping.csv", header = FALSE))
        storage.mode(scIdx) <- "integer"
        
        # --- Define the sparse dictionary learning parameters and run ---
        cEps <- 1e-6
        maxIter <- 30
        p <- 20
        
        paramXb <- list()
        paramXb\$K <- p
        paramXb\$D <- matrix(c(0.),nrow = 0,ncol=0)
        paramXb\$batch <- TRUE
        paramXb\$iter <- 1
        
        paramXb\$mode <- 'PENALTY'
        paramXb\$lambda <- 0.25 
        
        iRes_rep <- iterativeRUV(Y, cIdx, scIdx, paramXb, k=20, nu.coeff=0,
        cEps, maxIter,
        Wmethod='rep', wUpdate=11)
        
        # Save Replicate-based results
        saveRDS(iRes_rep, "iterative_ruv_rep_results.rds")
        write.csv(iRes_rep\$cY, "corrected_expression_rep.csv", row.names = TRUE)
        
        # --- Define parameters and run iterative RUV (SVD-based) ---
        paramXb <- list()
        paramXb\$K <- p
        paramXb\$D <- matrix(c(0.),nrow = 0,ncol=0)
        paramXb\$batch <- TRUE
        paramXb\$iter <- 1
        paramXb\$mode <- 'PENALTY'
        paramXb\$lambda <- 6e-2
        paramXb\$lambda2 <- 0
        
        iRes_svd <- iterativeRUV(Y, cIdx, scIdx=NULL, paramXb, k=nrow(Y), nu.coeff=1e-3/2,
        cEps, maxIter,
        Wmethod='svd', wUpdate=11)
        
        # Save SVD-based results
        saveRDS(iRes_svd, "iterative_ruv_svd_results.rds")
        write.csv(iRes_svd\$cY, "corrected_expression_svd.csv", row.names = TRUE)
        
        # --- Generate diagnostic PCA plots ---
        pdf("pca_comparison.pdf", width = 12, height = 4)
        par(mfrow = c(1, 3))
        
        # Uncorrected PCA
        pca_un <- prcomp(Y)
        plot(pca_un\$x[, 1:2], main = "Uncorrected", col = "blue", pch = 19, xlab = "PC1", ylab = "PC2")
        
        # Replicate-based Iterative RUV PCA
        pca_rep <- prcomp(iRes_rep\$cY)
        plot(pca_rep\$x[, 1:2], main = "Iterative RUV (Replicates)", col = "red", pch = 19, xlab = "PC1", ylab = "PC2")
        
        # SVD-based Iterative RUV PCA
        pca_svd <- prcomp(iRes_svd\$cY)
        plot(pca_svd\$x[, 1:2], main = "Iterative RUV (SVD)", col = "darkgreen", pch = 19, xlab = "PC1", ylab = "PC2")
        
        dev.off()

    writeLines(c(
        '"BIOC_RUVNORMALIZE_ITERATIVE_RUV":',
        paste0('    RUVnormalize: ', as.character(packageVersion('RUVnormalize')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_iterative_ruv.csv versions.yml
    """
}

workflow BIOC_RUVNORMALIZE_ITERATIVE_RUV_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv, negative_controls.txt, replicates_mapping.csv ] ]

    main:
    BIOC_RUVNORMALIZE_ITERATIVE_RUV(ch_input)

    emit:
    tables   = BIOC_RUVNORMALIZE_ITERATIVE_RUV.out.tables
    plots    = BIOC_RUVNORMALIZE_ITERATIVE_RUV.out.plots
    objects  = BIOC_RUVNORMALIZE_ITERATIVE_RUV.out.objects
    versions = BIOC_RUVNORMALIZE_ITERATIVE_RUV.out.versions
}
