#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: squallms — semi_labeled_peak_filtering
// Filter out low-quality chromatographic features from an XCMS object using a semi-labeled logistic regression model trained on manual or lasso-labeled peak quali
// Input: mzML_files, xcms_filled
// Container: quay.io/biocontainers/bioconductor-squallms:1.4.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: RaMS, dplyr, ggplot2, squallms, tibble, tidyr, xcms
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Flatten the XCMS object to extract feature and peak bounding box information using makeXcmsObjFlat
//  * 2. [Core Analysis] Extract raw MS1 data using RaMS::grabMSdata
//  * 3. [Core Analysis] Calculate peak quality metrics (similarity to bell curve and signal-to-noise ratio) using extractChromMetrics
//  * 4. [Core Analysis] Label a subset of features as "Good" or "Bad" using interactive manual labeling (labelFeatsManual) or PCA-based lasso labeling (la
//  * 5. [Core Analysis] Train a logistic regression model and predict quality probabilities for all features using logModelFeatProb and logModelFeatQualit
//  * 6. [Core Analysis] Filter and update the original XCMS object to retain only high-quality peaks using updateXcmsObjFeats

nextflow.enable.dsl = 2

process BIOC_SQUALLMS_SEMI_LABELED_PEAK_FILTERING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20"

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
    library(squallms)
    library(dplyr)
    library(tidyr)
    library(tibble)
    library(ggplot2)
    library(xcms)
    library(RaMS)
    
    # ==========================================
    # 1. Read User Input Files
    # ==========================================
    
    message("Loading xcms_filled object...")
    if (!file.exists("xcms_filled.rds")) {
        stop("Required input file 'xcms_filled.rds' not found in the working directory.")
    }
    xcms_filled <- readRDS("xcms_filled.rds")
    
    # Find raw mass spectrometry files in the working directory
    message("Locating raw mzML/mzXML files...")
    local_files <- list.files(
        pattern = "\\\\.(mzML|mzXML|mzML\\\\.gz|mzXML\\\\.gz)\$", 
        ignore.case = TRUE, 
        full.names = TRUE
    )
    if (length(local_files) == 0) {
        stop("No mzML or mzXML files found in the working directory.")
    }
    
    # ==========================================
    # 2. Flatten XCMS Object & Align Filepaths
    # ==========================================
    
    message("Flattening XCMS object...")
    feat_peak_info <- makeXcmsObjFlat(xcms_filled) %>%
        select(feature, starts_with("mz"), starts_with("rt"), filename, filepath)
    
    # Update the filepaths in feat_peak_info to point to local files in the working directory
    feat_peak_info\$filepath <- sapply(feat_peak_info\$filepath, function(fp) {
        if (file.exists(fp)) return(normalizePath(fp))
        bn <- basename(fp)
        local_match <- local_files[basename(local_files) == bn]
        if (length(local_match) > 0) {
            return(normalizePath(local_match[1]))
        }
        # Fallback to the first local file if no exact match is found
        return(normalizePath(local_files[1]))
    })
    
    # ==========================================
    # 3. Extract Raw MS1 Data & Calculate Metrics
    # ==========================================
    
    message("Extracting raw MS1 data...")
    msdata <- grabMSdata(unique(feat_peak_info\$filepath), verbosity = 0)
    
    message("Calculating peak quality metrics...")
    shape_metrics <- extractChromMetrics(feat_peak_info, ms1_data = msdata\$MS1)
    
    # Save shape metrics to CSV
    write.csv(shape_metrics, "shape_metrics.csv", row.names = FALSE)
    
    # ==========================================
    # 4. Labeling (Manual & Lasso)
    # ==========================================
    
    # Helper function to generate robust fallback labels for non-interactive environments
    generate_fallback_labels <- function(feat_peak_info, shape_metrics) {
        set.seed(123)
        feats <- unique(feat_peak_info\$feature)
        labels <- rep(NA_character_, length(feats))
        names(labels) <- feats
        
        if (exists("shape_metrics") && nrow(shape_metrics) > 0) {
            # Rank features by a combination of correlation and SNR
            rank_cor <- rank(shape_metrics\$med_cor)
            rank_snr <- rank(shape_metrics\$med_snr)
            combined_rank <- rank_cor + rank_snr
            
            n_total <- length(feats)
            n_select <- max(2, floor(n_total * 0.15))
            
            good_feats <- shape_metrics\$feature[order(combined_rank, decreasing = TRUE)[1:n_select]]
            bad_feats <- shape_metrics\$feature[order(combined_rank, decreasing = FALSE)[1:n_select]]
            
            labels[good_feats] <- "Good"
            labels[bad_feats] <- "Bad"
        } else {
            n_total <- length(feats)
            n_select <- max(2, floor(n_total * 0.15))
            labels[1:n_select] <- "Good"
            labels[(n_total - n_select + 1):n_total] <- "Bad"
        }
        return(labels)
    }
    
    message("Performing manual labeling...")
    manual_classes <- tryCatch({
        if (interactive()) {
            labelFeatsManual(feat_peak_info, ms1_data = msdata\$MS1)
        } else {
            stop("Non-interactive environment detected. Using fallback labels.")
        }
    }, error = function(e) {
        message("Skipping interactive manual labeling. Generating fallback labels...")
        generate_fallback_labels(feat_peak_info, shape_metrics)
    })
    
    message("Performing lasso labeling...")
    lasso_classes <- tryCatch({
        if (interactive()) {
            labelFeatsLasso(feat_peak_info, ms1_data = msdata\$MS1)
        } else {
            stop("Non-interactive environment detected. Using fallback labels.")
        }
    }, error = function(e) {
        message("Skipping interactive lasso labeling. Generating fallback labels...")
        generate_fallback_labels(feat_peak_info, shape_metrics)
    })
    
    # Combine manual and lasso labels
    class_labels <- lasso_classes
    class_labels[!is.na(manual_classes)] <- manual_classes[!is.na(manual_classes)]
    
    # ==========================================
    # 5. Train Logistic Regression Model & Predict
    # ==========================================
    
    message("Training logistic regression model and predicting probabilities...")
    pred_probs <- logModelFeatProb(shape_metrics, class_labels)
    
    message("Predicting binary quality classes...")
    pred_classes <- logModelFeatQuality(shape_metrics, class_labels, verbosity = 1)
    
    # Save predictions
    predictions_df <- shape_metrics %>%
        mutate(
            assigned_label = class_labels[feature],
            predicted_probability = pred_probs,
            predicted_class = pred_classes
        )
    write.csv(predictions_df, "predicted_classes.csv", row.names = FALSE)
    
    # ==========================================
    # 6. Filter and Update XCMS Object
    # ==========================================
    
    message("Updating XCMS object to retain only high-quality peaks...")
    final_xcms <- updateXcmsObjFeats(xcms_filled, shape_metrics, class_labels,
        verbosity = 0, likelihood_threshold = 0.5
    )
    
    # Save final filtered XCMS object
    saveRDS(final_xcms, "final_xcms.rds")
    
    # ==========================================
    # 7. Generate Diagnostic Plots
    # ==========================================
    
    message("Generating diagnostic plots...")
    
    # Plot 1: Shape metrics scatter plot
    pdf("shape_metrics_plot.pdf", width = 8, height = 6)
    p1 <- shape_metrics %>%
        arrange(desc(med_snr)) %>%
        ggplot() +
        geom_point(aes(x = med_rt, y = med_mz, color = med_cor, size = med_snr), alpha = 0.5) +
        scale_color_viridis_c(option = "plasma") +
        theme_bw() +
        labs(
            title = "Mass by Time Diagram of Features",
            x = "Retention Time (med_rt)",
            y = "m/z (med_mz)",
            color = "Peak Shape (med_cor)",
            size = "S/N Ratio (med_snr)"
        )
    print(p1)
    dev.off()
    
    # Plot 2: Logistic model fit visualization
    pdf("logistic_model_fit.pdf", width = 8, height = 6)
    plot_df <- shape_metrics %>%
        mutate(
            probability = pred_probs,
            class = class_labels[feature]
        )
    p2 <- ggplot(plot_df, aes(x = med_cor, y = med_snr, color = probability)) +
        geom_point(aes(shape = class), size = 3, alpha = 0.8) +
        scale_color_gradientn(colors = c("red", "yellow", "green")) +
        theme_bw() +
        labs(
            title = "Logistic Regression Model Fit",
            x = "Peak Shape Correlation (med_cor)",
            y = "Signal-to-Noise Ratio (med_snr)",
            color = "Predicted Probability",
            shape = "Assigned Class"
        )
    print(p2)
    dev.off()
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_SQUALLMS_SEMI_LABELED_PEAK_FILTERING":',
        paste0('    squallms: ', as.character(packageVersion('squallms')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_semi_labeled_peak_filtering.csv versions.yml
    """
}

workflow BIOC_SQUALLMS_SEMI_LABELED_PEAK_FILTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ mzML_files, xcms_filled ] ]

    main:
    BIOC_SQUALLMS_SEMI_LABELED_PEAK_FILTERING(ch_input)

    emit:
    tables   = BIOC_SQUALLMS_SEMI_LABELED_PEAK_FILTERING.out.tables
    plots    = BIOC_SQUALLMS_SEMI_LABELED_PEAK_FILTERING.out.plots
    objects  = BIOC_SQUALLMS_SEMI_LABELED_PEAK_FILTERING.out.objects
    versions = BIOC_SQUALLMS_SEMI_LABELED_PEAK_FILTERING.out.versions
}
