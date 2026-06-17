#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: PrInCE — predict_interactions_workflow
// Predict binary protein-protein interactions from co-elution proteomics data using a machine learning classifier trained on gold-standard complexes.
// Input: co_elution_matrix.csv, gold_standard_complexes.rds
// Container: quay.io/biocontainers/bioconductor-prince:1.26.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: PrInCE
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Load User Input Files
//  * 2. [Core Analysis] Fit Gaussian Mixture Models
//  * 3. [Core Analysis] Calculate Pairwise Features
//  * 4. [Core Analysis] Predict Interactions
//  * 5. [Core Analysis] Plot and Save Precision Curve
//  * 6. [Core Analysis] Threshold Network at User-Defined Precision

nextflow.enable.dsl = 2

process BIOC_PRINCE_PREDICT_INTERACTIONS_WORKFLOW {
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
    .bm_deps <- c("PrInCE")
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
        library(PrInCE)
        
        # ==========================================
        # --- Load User Input Files ---
        # ==========================================
        # Read the co-elution matrix (CSV format, first column as row names/protein IDs)
        co_elution_file <- "co_elution_matrix.csv"
        if (!file.exists(co_elution_file)) {
          stop(paste("Required input file missing:", co_elution_file))
        }
        profiles_df <- read.csv(co_elution_file, row.names = 1, check.names = FALSE)
        profiles <- as.matrix(profiles_df)
        
        # Read the gold standard complexes (RDS format, list of protein vectors)
        gold_standard_file <- "gold_standard_complexes.rds"
        if (!file.exists(gold_standard_file)) {
          stop(paste("Required input file missing:", gold_standard_file))
        }
        gold_standard <- readRDS(gold_standard_file)
        
        # ==========================================
        # --- Fit Gaussian Mixture Models ---
        # ==========================================
        # Set seed to ensure reproducible output
        set.seed(0)
        
        message("Fitting Gaussian mixture models to elution profiles...")
        # Fit Gaussians using default parameters
        gauss <- build_gaussians(profiles)
        
        # Save fitted Gaussians
        saveRDS(gauss, "fitted_gaussians.rds")
        
        # Filter profiles that were not successfully fit
        profiles_filtered <- profiles[names(gauss), ]
        
        # ==========================================
        # --- Calculate Pairwise Features ---
        # ==========================================
        message("Calculating pairwise features...")
        # Calculate features
        feat <- calculate_features(profiles_filtered, gauss)
        
        # Save calculated features
        write.csv(feat, "calculated_features.csv", row.names = FALSE)
        
        # ==========================================
        # --- Predict Interactions ---
        # ==========================================
        message("Predicting protein-protein interactions...")
        # Convert gold standard list to an adjacency matrix
        reference <- adjacency_matrix_from_list(gold_standard)
        
        # Set seed to ensure reproducible classifier training
        set.seed(0)
        
        # Predict interactions using SVM classifier with 10-fold cross-validation
        ppi <- predict_interactions(feat, reference, 
                                    classifier = "SVM",
                                    models = 10, 
                                    cv_folds = 10)
        
        # Save raw predicted interactions
        saveRDS(ppi, "predicted_interactions.rds")
        write.csv(ppi, "predicted_interactions.csv", row.names = FALSE)
        
        # ==========================================
        # --- Plot and Save Precision Curve ---
        # ==========================================
        message("Plotting precision curve...")
        pdf("precision_curve.pdf", width = 6, height = 6)
        # Safely determine the number of points to plot (up to 20,000)
        n_points <- min(20000, length(ppi\$precision))
        precision_subset <- ppi\$precision[seq_len(n_points)]
        plot(precision_subset, type = "l", col = "blue", lwd = 2,
             main = "PrInCE Interaction Prediction Precision",
             xlab = "Ranked Interactions", ylab = "Precision")
        dev.off()
        
        # ==========================================
        # --- Threshold Network at User-Defined Precision ---
        # ==========================================
        message("Filtering predicted interactions at precision threshold...")
        # Threshold the network at 70% precision as documented
        net <- threshold_precision(ppi, threshold = 0.7)
        
        # Save the final thresholded network
        write.csv(net, "thresholded_network.csv", row.names = FALSE)
        
        message(paste("Pipeline completed successfully. Reconstructed network contains", nrow(net), "interactions."))

    writeLines(c(
        '"BIOC_PRINCE_PREDICT_INTERACTIONS_WORKFLOW":',
        paste0('    PrInCE: ', as.character(packageVersion('PrInCE')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_predict_interactions_workflow.csv versions.yml
    """
}

workflow BIOC_PRINCE_PREDICT_INTERACTIONS_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ co_elution_matrix.csv, gold_standard_complexes.rds ] ]

    main:
    BIOC_PRINCE_PREDICT_INTERACTIONS_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_PRINCE_PREDICT_INTERACTIONS_WORKFLOW.out.tables
    plots    = BIOC_PRINCE_PREDICT_INTERACTIONS_WORKFLOW.out.plots
    objects  = BIOC_PRINCE_PREDICT_INTERACTIONS_WORKFLOW.out.objects
    versions = BIOC_PRINCE_PREDICT_INTERACTIONS_WORKFLOW.out.versions
}
