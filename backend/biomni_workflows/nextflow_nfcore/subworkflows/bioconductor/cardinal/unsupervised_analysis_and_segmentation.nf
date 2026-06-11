#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Cardinal — unsupervised_analysis_and_segmentation
// Perform dimension reduction, spatial clustering, and feature colocalization on unlabeled MSI datasets.
// Input: processed_msi.rds
// Container: quay.io/biocontainers/bioconductor-cardinal:3.12.1--r45hdfd78af_0
// R packages: Cardinal
// Bioconductor: 3.20 | R: 4.4
// Requires: Cardinal
// Visualizations: image plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Perform Principal Components Analysis using PCA
//  * 2. [Core Analysis] Perform Non-negative Matrix Factorization using NMF
//  * 3. [Core Analysis] Find colocalized features using colocalized
//  * 4. [Core Analysis] Segment images using spatialShrunkenCentroids clustering
//  * 5. [Core Analysis] Perform single-feature segmentation using spatialDGMM

nextflow.enable.dsl = 2

process BIOC_CARDINAL_UNSUPERVISED_ANALYSIS_AND_SEGMENTATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-imaging:3.20"

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
    .bm_deps <- c("Cardinal")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
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
        library(Cardinal)
        
        # Read the user input file
        input_file <- "processed_msi.rds"
        if (!file.exists(input_file)) {
          stop(paste("Required input file missing:", input_file))
        }
        
        mse <- readRDS(input_file)
        
        # Set up PDF to capture all plots
        pdf("unsupervised_analysis_plots.pdf", width=11, height=8.5)
        
        # 1. Perform Principal Components Analysis using PCA
        message("Running PCA...")
        pca <- PCA(mse, ncomp=3)
        saveRDS(pca, "pca_results.rds")
        
        tryCatch({
          image(pca, type="x", superpose=FALSE, layout=c(1,3), scale=TRUE)
        }, error = function(e) {
          warning("Failed to plot PCA image: ", e\$message)
        })
        
        tryCatch({
          plot(pca, type="rotation", superpose=FALSE, layout=c(1,3), linewidth=2)
        }, error = function(e) {
          warning("Failed to plot PCA rotation: ", e\$message)
        })
        
        tryCatch({
          plot(pca, type="x", groups=run(mse), linewidth=2)
        }, error = function(e) {
          warning("Failed to plot PCA groups: ", e\$message)
        })
        
        
        # 2. Perform Non-negative Matrix Factorization using NMF
        message("Running NMF...")
        nmf <- NMF(mse, ncomp=3)
        saveRDS(nmf, "nmf_results.rds")
        
        tryCatch({
          image(nmf, type="x", superpose=FALSE, layout=c(1,3), scale=TRUE)
        }, error = function(e) {
          warning("Failed to plot NMF image: ", e\$message)
        })
        
        tryCatch({
          plot(nmf, type="activation", superpose=FALSE, layout=c(1,3), linewidth=2)
        }, error = function(e) {
          warning("Failed to plot NMF activation: ", e\$message)
        })
        
        
        # 3. Find colocalized features using colocalized
        message("Running feature colocalization...")
        tryCatch({
          coloc <- colocalized(mse, mz=mz(mse)[1])
          write.csv(as.data.frame(coloc), "colocalized_features.csv", row.names=TRUE)
        }, error = function(e) {
          warning("Colocalization failed: ", e\$message)
        })
        
        
        # 4. Segment images using spatialShrunkenCentroids clustering
        message("Running Spatial Shrunken Centroids...")
        ssc <- spatialShrunkenCentroids(mse, r=1, k=3, s=c(0,6,12,18))
        saveRDS(ssc, "ssc_results.rds")
        
        tryCatch({
          image(ssc, i=1:3, type="probability", layout=c(1,3))
        }, error = function(e) {
          warning("Failed to plot SSC probability image: ", e\$message)
        })
        
        tryCatch({
          plot(ssc, i=1:3, type="statistic", layout=c(1,3), linewidth=2, annPeaks="circle")
        }, error = function(e) {
          warning("Failed to plot SSC statistics: ", e\$message)
        })
        
        tryCatch({
          ssc_top <- topFeatures(ssc[[2L]])
          write.csv(as.data.frame(ssc_top), "ssc_top_features.csv", row.names=TRUE)
        }, error = function(e) {
          warning("Failed to extract top features from SSC: ", e\$message)
        })
        
        
        # 5. Perform single-feature segmentation using spatialDGMM
        message("Running Spatial DGMM...")
        dgmm <- spatialDGMM(mse, r=1, k=3, weights="gaussian")
        saveRDS(dgmm, "dgmm_results.rds")
        
        tryCatch({
          n_features <- min(3, nrow(mse))
          image(dgmm, i=1:n_features, layout=c(1, n_features))
        }, error = function(e) {
          warning("Failed to plot DGMM image: ", e\$message)
        })
        
        tryCatch({
          coloc2 <- colocalized(dgmm, mz=mz(mse)[1])
          write.csv(as.data.frame(coloc2), "colocalized_dgmm_features.csv", row.names=TRUE)
        }, error = function(e) {
          warning("Colocalization with DGMM failed: ", e\$message)
        })
        
        # Close the graphics device
        dev.off()
        message("Pipeline completed successfully. Outputs saved.")

    writeLines(c(
        '"BIOC_CARDINAL_UNSUPERVISED_ANALYSIS_AND_SEGMENTATION":',
        paste0('    Cardinal: ', as.character(packageVersion('Cardinal')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_unsupervised_analysis_and_segmentation.csv versions.yml
    """
}

workflow BIOC_CARDINAL_UNSUPERVISED_ANALYSIS_AND_SEGMENTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ processed_msi.rds ] ]

    main:
    BIOC_CARDINAL_UNSUPERVISED_ANALYSIS_AND_SEGMENTATION(ch_input)

    emit:
    tables   = BIOC_CARDINAL_UNSUPERVISED_ANALYSIS_AND_SEGMENTATION.out.tables
    plots    = BIOC_CARDINAL_UNSUPERVISED_ANALYSIS_AND_SEGMENTATION.out.plots
    objects  = BIOC_CARDINAL_UNSUPERVISED_ANALYSIS_AND_SEGMENTATION.out.objects
    versions = BIOC_CARDINAL_UNSUPERVISED_ANALYSIS_AND_SEGMENTATION.out.versions
}
