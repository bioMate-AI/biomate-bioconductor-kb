#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: timeOmics — multi_block_omics_clustering
// Integrate and cluster longitudinal features from three or more omics datasets, identify signatures, and perform post-hoc validation.
// Input: profile.filtered, timeOmics.simdata$Z, timeOmics.simdata$Y
// Container: quay.io/biocontainers/bioconductor-timeomics:1.22.0--r45h575d39b_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: mixOmics, tidyverse, timeOmics
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Perform multi-block PLS and optimize the number of components
//  * 2. [Visualization & Output] Extract clusters and plot longitudinal profiles
//  * 3. [Core Analysis] Optimize feature selection across all blocks using multi-block sparse PLS
//  * 4. [Core Analysis] Perform post-hoc validation using proportionality distance and Wilcoxon U-tests

nextflow.enable.dsl = 2

process BIOC_TIMEOMICS_MULTI_BLOCK_OMICS_CLUSTERING {
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
        library(timeOmics)
        library(mixOmics)
        library(tidyverse)
        
        # Helper function to robustly read input files (RDS or CSV)
        read_input <- function(filename) {
          if (!file.exists(filename)) {
            stop(paste("Required input file missing:", filename))
          }
          obj <- tryCatch({
            readRDS(filename)
          }, error = function(e) {
            tryCatch({
              as.matrix(read.csv(filename, row.names = 1, check.names = FALSE))
            }, error = function(e2) {
              stop(paste("Failed to read file", filename, "as RDS or CSV."))
            })
          })
          return(obj)
        }
        
        # -----------------------------------------------------------------------------
        # Stage 0: Read User Input Files
        # -----------------------------------------------------------------------------
        profile.filtered <- read_input("profile.filtered")
        timeOmics.simdata_Z <- read_input("timeOmics.simdata\$Z")
        timeOmics.simdata_Y <- read_input("timeOmics.simdata\$Y")
        
        # Construct the multi-block structures
        X <- list("X" = profile.filtered, "Z" = timeOmics.simdata_Z)
        Y <- as.matrix(timeOmics.simdata_Y)
        
        # -----------------------------------------------------------------------------
        # Stage 1: Perform multi-block PLS and optimize the number of components
        # -----------------------------------------------------------------------------
        block.pls.res <- block.pls(X=X, Y=Y, ncomp = 5, 
                                   scale = FALSE, mode = "canonical")
        
        block.ncomp <- getNcomp(block.pls.res, X=X, Y=Y, 
                                scale = FALSE, mode = "canonical")
        
        # Save the component optimization plot
        pdf("block_pls_ncomp_plot.pdf")
        plot(block.ncomp)
        dev.off()
        
        # Re-run block PLS with optimized components
        block.pls.res <- block.pls(X=X, Y=Y, ncomp = block.ncomp\$choice.ncomp, scale = FALSE, mode = "canonical")
        
        # -----------------------------------------------------------------------------
        # Stage 2: Extract clusters and plot longitudinal profiles
        # -----------------------------------------------------------------------------
        block.pls.cluster <- getCluster(block.pls.res)
        
        # Save the initial cluster assignments
        write.csv(block.pls.cluster, "block_pls_clusters.csv", row.names = FALSE)
        
        # Save the longitudinal profile plot
        pdf("block_pls_long_plot.pdf")
        print(plotLong(block.pls.res))
        dev.off()
        
        # -----------------------------------------------------------------------------
        # Stage 3: Optimize feature selection across all blocks using multi-block sparse PLS
        # -----------------------------------------------------------------------------
        test.list.keepX <- list("X" = 1:min(10, ncol(X[["X"]])), 
                                "Z" = 1:min(8, ncol(X[["Z"]])))
        test.keepY <- 1:min(6, ncol(Y))
        
        tune.block.res <- tuneCluster.block.spls(X= X, Y= Y, 
                                                 test.list.keepX=test.list.keepX, 
                                                 test.keepY= test.keepY, 
                                                 scale=FALSE, 
                                                 mode = "canonical", 
                                                 ncomp = block.ncomp\$choice.ncomp)
        
        # Fit the final sparse multi-block PLS model
        block.pls.res <- block.spls(X=X, Y=Y, 
                                    ncomp = block.ncomp\$choice.ncomp, 
                                    scale = FALSE, 
                                    mode = "canonical", 
                                    keepX = tune.block.res\$choice.keepX, 
                                    keepY = tune.block.res\$choice.keepY)
        
        # Save the final sparse model object
        saveRDS(block.pls.res, "block_spls_model.rds")
        
        # Save the sparse model cluster assignments
        sparse_clusters <- getCluster(block.pls.res)
        write.csv(sparse_clusters, "block_spls_clusters.csv", row.names = FALSE)
        
        # Save the sparse model longitudinal profile plot
        pdf("block_spls_long_plot.pdf")
        print(plotLong(block.pls.res))
        dev.off()
        
        # -----------------------------------------------------------------------------
        # Stage 4: Perform post-hoc validation using proportionality distance and Wilcoxon U-tests
        # -----------------------------------------------------------------------------
        res <- proportionality(block.pls.res)
        
        # Save proportionality distance matrix
        write.csv(res\$propr.distance, "proportionality_distance.csv", row.names = TRUE)
        
        # Save Wilcoxon U-test p-values
        pval.propr <- res\$pvalue
        write.csv(pval.propr, "proportionality_pvalues.csv", row.names = FALSE)
        
        # Save the post-hoc validation plot
        pdf("proportionality_plot.pdf")
        plot(res)
        dev.off()

    writeLines(c(
        '"BIOC_TIMEOMICS_MULTI_BLOCK_OMICS_CLUSTERING":',
        paste0('    timeOmics: ', as.character(packageVersion('timeOmics')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multi_block_omics_clustering.csv versions.yml
    """
}

workflow BIOC_TIMEOMICS_MULTI_BLOCK_OMICS_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ profile.filtered, timeOmics.simdata$Z, timeOmics.simdata$Y ] ]

    main:
    BIOC_TIMEOMICS_MULTI_BLOCK_OMICS_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_TIMEOMICS_MULTI_BLOCK_OMICS_CLUSTERING.out.tables
    plots    = BIOC_TIMEOMICS_MULTI_BLOCK_OMICS_CLUSTERING.out.plots
    objects  = BIOC_TIMEOMICS_MULTI_BLOCK_OMICS_CLUSTERING.out.objects
    versions = BIOC_TIMEOMICS_MULTI_BLOCK_OMICS_CLUSTERING.out.versions
}
