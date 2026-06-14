#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Cardinal — supervised_classification
// Train and cross-validate classification models (PLS and Spatial Shrunken Centroids) to predict pixel classes.
// Input: labeled_msi.rds
// Container: quay.io/biocontainers/bioconductor-cardinal:3.12.1--r45hdfd78af_0
// R packages: Cardinal
// Bioconductor: 3.20 | R: 4.4
// Requires: Cardinal
// Visualizations: image plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Perform cross-validated PLS using crossValidate with PLS
//  * 2. [Core Analysis] Fit final PLS model using PLS
//  * 3. [Core Analysis] Perform cross-validated Spatial Shrunken Centroids classification using crossValidate with spatialShrunkenCentroids
//  * 4. [Core Analysis] Fit final Spatial Shrunken Centroids model using spatialShrunkenCentroids

nextflow.enable.dsl = 2

process BIOC_CARDINAL_SUPERVISED_CLASSIFICATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-imaging:3.20-deps"

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
        
        # 1. Read the input file
        input_file <- "labeled_msi.rds"
        if (!file.exists(input_file)) {
          stop(paste("Input file", input_file, "not found in the working directory."))
        }
        
        mse2 <- readRDS(input_file)
        
        # Ensure class labels exist in pixel metadata
        if (is.null(mse2\$class)) {
          stop("The input MSImagingExperiment object must contain a 'class' column in its pixel metadata.")
        }
        
        # Ensure run factor is set up correctly for folds
        if (is.null(run(mse2)) || length(unique(run(mse2))) < 2) {
          # If there's only one run, crossValidate will fail with run(mse2) as folds.
          # We create synthetic folds based on random sampling.
          set.seed(123)
          cv_folds <- factor(sample(1:3, dim(mse2)[2], replace=TRUE))
        } else {
          cv_folds <- factor(run(mse2))
        }
        
        # 2. Perform cross-validated PLS
        message("Running PLS cross-validation...")
        cv_pls <- crossValidate(x=mse2, y=mse2\$class, .method=PLS, ncomp=1:5, folds=cv_folds)
        saveRDS(cv_pls, "cv_pls.rds")
        
        # Extract best ncomp
        pls_summary <- as.data.frame(summary(cv_pls))
        if ("Accuracy" %in% names(pls_summary)) {
          best_ncomp <- pls_summary\$ncomp[which.max(pls_summary\$Accuracy)]
        } else {
          best_ncomp <- pls_summary\$ncomp[1]
        }
        message(paste("Selected best PLS ncomp:", best_ncomp))
        
        # 3. Fit final PLS model
        message("Fitting final PLS model...")
        pls <- PLS(mse2, y=mse2\$class, ncomp=best_ncomp)
        saveRDS(pls, "pls_model.rds")
        
        # Plot PLS results
        message("Saving PLS plots...")
        pdf("pls_plots.pdf", width=11, height=8.5)
        image(pls, type="response", layout=c(1,3), scale=TRUE)
        plot(pls, type="coefficients", linewidth=2, annPeaks=10)
        plot(pls, type="scores", groups=mse2\$class, linewidth=2)
        dev.off()
        
        # 4. Perform cross-validated Spatial Shrunken Centroids classification
        message("Running Spatial Shrunken Centroids cross-validation...")
        cv_ssc <- crossValidate(x=mse2, y=mse2\$class, .method=spatialShrunkenCentroids, r=2, s=c(0,3,6,9,12,15,18), folds=cv_folds)
        saveRDS(cv_ssc, "cv_ssc.rds")
        
        # Extract best s
        ssc_summary <- as.data.frame(summary(cv_ssc))
        if ("Accuracy" %in% names(ssc_summary)) {
          best_s <- ssc_summary\$s[which.max(ssc_summary\$Accuracy)]
        } else {
          best_s <- ssc_summary\$s[1]
        }
        message(paste("Selected best SSC s:", best_s))
        
        # 5. Fit final Spatial Shrunken Centroids model
        message("Fitting final Spatial Shrunken Centroids model...")
        ssc2 <- spatialShrunkenCentroids(mse2, y=mse2\$class, r=2, s=best_s)
        saveRDS(ssc2, "ssc_model.rds")
        
        # Plot SSC results
        message("Saving Spatial Shrunken Centroids plots...")
        pdf("ssc_plots.pdf", width=11, height=8.5)
        image(ssc2, type="probability", layout=c(1,3))
        plot(ssc2, type="statistic", linewidth=2, annPeaks=10)
        dev.off()
        
        # Extract and save top features
        message("Extracting top features...")
        ssc2_top <- topFeatures(ssc2)
        write.csv(as.data.frame(ssc2_top), "ssc2_top_features.csv", row.names=FALSE)
        
        message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_CARDINAL_SUPERVISED_CLASSIFICATION":',
        paste0('    Cardinal: ', as.character(packageVersion('Cardinal')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_supervised_classification.csv versions.yml
    """
}

workflow BIOC_CARDINAL_SUPERVISED_CLASSIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ labeled_msi.rds ] ]

    main:
    BIOC_CARDINAL_SUPERVISED_CLASSIFICATION(ch_input)

    emit:
    tables   = BIOC_CARDINAL_SUPERVISED_CLASSIFICATION.out.tables
    plots    = BIOC_CARDINAL_SUPERVISED_CLASSIFICATION.out.plots
    objects  = BIOC_CARDINAL_SUPERVISED_CLASSIFICATION.out.objects
    versions = BIOC_CARDINAL_SUPERVISED_CLASSIFICATION.out.versions
}
