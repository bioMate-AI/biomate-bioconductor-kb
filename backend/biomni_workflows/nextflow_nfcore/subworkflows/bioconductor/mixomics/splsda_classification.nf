#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mixOmics — splsda_classification
// Classify samples into known groups and identify a minimal diagnostic molecular signature.
// Input: expression_matrix.csv, sample_groups.csv
// Container: quay.io/biocontainers/bioconductor-mixomics:6.34.0--r45h575d39b_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: mixOmics
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run exploratory PCA using pca
//  * 2. [Core Analysis] Tune the number of components for PLS-DA using plsda and perf
//  * 3. [Core Analysis] Run final PLS-DA using plsda
//  * 4. [Core Analysis] Tune the number of variables to select per component using tune.splsda
//  * 5. [Core Analysis] Run final sparse PLS-DA using splsda
//  * 6. [Core Analysis] Evaluate classification performance and feature stability using perf
//  * 7. [Visualization & Output] Visualize sample separation, prediction background, and selected features using plotIndiv, background.predict, plotVar, plotLoadin
//  * 8. [Core Analysis] Predict classes of new samples using predict
//  * 9. [Core Analysis] Calculate ROC curves and AUC using auroc

nextflow.enable.dsl = 2

process BIOC_MIXOMICS_SPLSDA_CLASSIFICATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20-slim"

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
    .bm_deps <- c("mixOmics")
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
        library(mixOmics)
        
        # ==========================================
        # 0. DATA LOADING & PREPARATION
        # ==========================================
        
        # Check if required input files exist
        if (!file.exists("expression_matrix.csv") || !file.exists("sample_groups.csv")) {
          stop("Required input files 'expression_matrix.csv' and/or 'sample_groups.csv' are missing.")
        }
        
        # Read user input files
        X_raw <- read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE)
        Y_raw <- read.csv("sample_groups.csv", row.names = 1, check.names = FALSE)
        
        # Align samples between X and Y
        common_samples <- intersect(rownames(X_raw), rownames(Y_raw))
        if (length(common_samples) == 0) {
          stop("No matching sample names found between expression_matrix.csv and sample_groups.csv.")
        }
        
        X_mat <- as.matrix(X_raw[common_samples, , drop = FALSE])
        Y_vec <- as.factor(Y_raw[common_samples, 1])
        
        # Reconstruct the srbct-like list structure to faithfully reproduce documented code
        srbct <- list(
          gene = X_mat,
          class = Y_vec
        )
        
        # Assign variables as in the documented code
        X <- srbct\$gene
        Y <- srbct\$class 
        
        # Print basic data summaries
        print("Dimensions of X:")
        print(dim(X))
        print("Length of Y:")
        print(length(Y))
        print("Summary of Y:")
        print(summary(Y))
        
        # Open PDF device to capture all plots
        pdf("splsda_classification_plots.pdf", width = 10, height = 8)
        
        # ==========================================
        # 1. EXPLORATORY PCA
        # ==========================================
        pca.srbct <- pca(X, ncomp = 3, scale = TRUE)
        plotIndiv(pca.srbct, group = srbct\$class, ind.names = FALSE,
                  legend = TRUE, 
                  title = 'SRBCT, PCA comp 1 - 2')
        
        # ==========================================
        # 2. TUNE NUMBER OF COMPONENTS FOR PLS-DA
        # ==========================================
        plsda.srbct <- plsda(X, Y, ncomp = max(1, min(10, nrow(X) - 1, ncol(X))))
        
        set.seed(30) # For reproducibility
        perf.plsda.srbct <- perf(plsda.srbct, validation = 'Mfold', folds = 3, 
                                 progressBar = FALSE,  # Set to TRUE to track progress
                                 nrepeat = 10)         # We suggest nrepeat = 50
        
        plot(perf.plsda.srbct, sd = TRUE, legend.position = 'horizontal')
        
        # ==========================================
        # 3. RUN FINAL PLS-DA
        # ==========================================
        final.plsda.srbct <- plsda(X, Y, ncomp = 3)
        
        plotIndiv(final.plsda.srbct, ind.names = FALSE, legend=TRUE,
                  comp=c(1,2), ellipse = TRUE, 
                  title = 'PLS-DA on SRBCT comp 1-2',
                  X.label = 'PLS-DA comp 1', Y.label = 'PLS-DA comp 2')
        
        plotIndiv(final.plsda.srbct, ind.names = FALSE, legend=TRUE,
                  comp=c(2,3), ellipse = TRUE, 
                  title = 'PLS-DA on SRBCT comp 2-3',
                  X.label = 'PLS-DA comp 2', Y.label = 'PLS-DA comp 3')
        
        set.seed(30) # For reproducibility
        perf.final.plsda.srbct <- perf(final.plsda.srbct, validation = 'Mfold', 
                                       folds = 3, 
                                       progressBar = FALSE, # TRUE to track progress
                                       nrepeat = 10) # we recommend 50 
        
        # Print error rates
        print("BER for max.dist:")
        print(perf.final.plsda.srbct\$error.rate\$BER[, 'max.dist'])
        print("Class error rate for max.dist:")
        print(perf.final.plsda.srbct\$error.rate.class\$max.dist)
        
        # Background prediction visualization
        background.max <- background.predict(final.plsda.srbct, 
                                             comp.predicted = 2,
                                             dist = 'max.dist') 
        
        plotIndiv(final.plsda.srbct, comp = 1:2, group = srbct\$class,
                  ind.names = FALSE, title = 'Maximum distance',
                  legend = TRUE,  background = background.max)
        
        # ==========================================
        # 4. TUNE VARIABLES TO SELECT PER COMPONENT
        # ==========================================
        # Define grid of keepX values, ensuring we do not exceed the number of available features
        list.keepX <- c(1:10, seq(20, 100, 10))
        list.keepX <- list.keepX[list.keepX <= ncol(X)]
        if (length(list.keepX) == 0) {
          list.keepX <- c(1:min(5, ncol(X)))
        }
        
        # Run tuning
        tune.splsda.srbct <- tune.splsda(X, Y, ncomp = 4, validation = 'Mfold', 
                                         folds = 5, dist = 'max.dist', 
                                         test.keepX = list.keepX, nrepeat = 10)
        
        print("Tuning Error Rates (Head):")
        print(head(tune.splsda.srbct\$error.rate))
        
        plot(tune.splsda.srbct, sd = TRUE)
        
        print("Optimal number of components:")
        print(tune.splsda.srbct\$choice.ncomp\$ncomp)
        print("Optimal keepX:")
        print(tune.splsda.srbct\$choice.keepX)
        
        # Extract optimal parameters with robust fallbacks
        ncomp <- tune.splsda.srbct\$choice.ncomp\$ncomp 
        if (is.null(ncomp) || length(ncomp) == 0 || ncomp < 2) {
          ncomp <- 2
        }
        select.keepX <- tune.splsda.srbct\$choice.keepX[1:ncomp]  
        if (any(is.na(select.keepX))) {
          select.keepX[is.na(select.keepX)] <- min(10, ncol(X))
        }
        
        # ==========================================
        # 5. RUN FINAL SPARSE PLS-DA
        # ==========================================
        splsda.srbct <- splsda(X, Y, ncomp = ncomp, keepX = select.keepX) 
        
        # ==========================================
        # 6. EVALUATE CLASSIFICATION PERFORMANCE & STABILITY
        # ==========================================
        set.seed(34)  
        perf.splsda.srbct <- perf(splsda.srbct, validation = 'Mfold', folds = 5, 
                                  dist = 'max.dist', nrepeat = 10, progressBar = FALSE)
        
        print("sPLS-DA Classification Performance (BER):")
        print(perf.splsda.srbct\$error.rate\$BER)
        
        # ==========================================
        # 7. VISUALIZE SAMPLE SEPARATION, BACKGROUND, & FEATURES
        # ==========================================
        # Sample separation
        plotIndiv(splsda.srbct, comp = 1:2, group = srbct\$class,
                  ind.names = FALSE, title = 'sPLS-DA Sample Plot',
                  legend = TRUE)
        
        # Prediction background
        background.max.splsda <- background.predict(splsda.srbct, 
                                                    comp.predicted = 2,
                                                    dist = 'max.dist') 
        plotIndiv(splsda.srbct, comp = 1:2, group = srbct\$class,
                  ind.names = FALSE, title = 'sPLS-DA Maximum Distance Background',
                  legend = TRUE, background = background.max.splsda)
        
        # Variable correlation circle plot
        plotVar(splsda.srbct, comp = 1:2, var.names = FALSE, 
                title = 'sPLS-DA Correlation Circle Plot')
        
        # Loadings plot for the first component
        plotLoadings(splsda.srbct, comp = 1, title = 'sPLS-DA Loadings on Comp 1')
        
        # Clustered Image Map (CIM)
        cim(splsda.srbct, comp = 1:2, title = 'sPLS-DA Clustered Image Map')
        
        # ==========================================
        # 8. PREDICT CLASSES OF SAMPLES
        # ==========================================
        predict.splsda <- predict(splsda.srbct, X)
        
        # ==========================================
        # 9. CALCULATE ROC CURVES AND AUC
        # ==========================================
        auc.splsda <- auroc(splsda.srbct, roc.comp = 1)
        
        # Close PDF device
        dev.off()
        
        # ==========================================
        # 10. SAVE OUTPUTS TO DISK
        # ==========================================
        # Save RDS models
        saveRDS(pca.srbct, "pca_model.rds")
        saveRDS(final.plsda.srbct, "plsda_model.rds")
        saveRDS(splsda.srbct, "splsda_model.rds")
        
        # Save CSV tables
        write.csv(as.data.frame(perf.final.plsda.srbct\$error.rate\$BER), "plsda_error_rate_ber.csv")
        write.csv(as.data.frame(perf.final.plsda.srbct\$error.rate.class\$max.dist), "plsda_error_rate_class.csv")
        write.csv(as.data.frame(tune.splsda.srbct\$error.rate), "splsda_tuning_error_rate.csv")
        write.csv(as.data.frame(perf.splsda.srbct\$error.rate\$BER), "splsda_error_rate_ber.csv")
        
        # Extract and save selected features per component
        selected_features <- list()
        for (i in 1:ncomp) {
          selected_features[[paste0("comp", i)]] <- selectVar(splsda.srbct, comp = i)\$name
        }
        max_len <- max(sapply(selected_features, length))
        selected_features_df <- as.data.frame(lapply(selected_features, function(x) {
          c(x, rep(NA, max_len - length(x)))
        }))
        write.csv(selected_features_df, "selected_features.csv", row.names = FALSE)
        
        print("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_MIXOMICS_SPLSDA_CLASSIFICATION":',
        paste0('    mixOmics: ', as.character(packageVersion('mixOmics')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_splsda_classification.csv versions.yml
    """
}

workflow BIOC_MIXOMICS_SPLSDA_CLASSIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv, sample_groups.csv ] ]

    main:
    BIOC_MIXOMICS_SPLSDA_CLASSIFICATION(ch_input)

    emit:
    tables   = BIOC_MIXOMICS_SPLSDA_CLASSIFICATION.out.tables
    plots    = BIOC_MIXOMICS_SPLSDA_CLASSIFICATION.out.plots
    objects  = BIOC_MIXOMICS_SPLSDA_CLASSIFICATION.out.objects
    versions = BIOC_MIXOMICS_SPLSDA_CLASSIFICATION.out.versions
}
