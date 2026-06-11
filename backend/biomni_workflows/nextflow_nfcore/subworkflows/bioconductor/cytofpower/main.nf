#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CyTOFpower — cytofpower_parameter_estimation_and_simulation
// Estimate Negative Binomial parameters and fold changes from real CyTOF intensity data, run an offline power simulation, and prepare inputs for the CyTOFpower Sh
// Input: intensity.csv, coldata.csv
// Container: 1.16.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: CyTOFpower
// Visualizations: bar plot
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CYTOFPOWER_CYTOFPOWER_PARAMETER_ESTIMATION_AND_SIMULATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20"

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
    .bm_deps <- c("CyTOFpower", "MASS")
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
    
    # --- Load required libraries and validate inputs ---
    library(CyTOFpower)
    library(MASS)
    
    set.seed(42)
    
    # Check for input files
    if (!file.exists("intensity.csv") || !file.exists("coldata.csv")) {
      stop("Required input files 'intensity.csv' or 'coldata.csv' are missing.")
    }
    
    # Read inputs
    intensity_df <- read.csv("intensity.csv", check.names = FALSE)
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    # --- Preprocess and align data ---
    if (!"feature_id" %in% colnames(intensity_df)) {
      colnames(intensity_df)[1] <- "feature_id"
    }
    rownames(intensity_df) <- intensity_df\$feature_id
    sample_cols <- setdiff(colnames(intensity_df), "feature_id")
    intensity_matrix <- as.matrix(intensity_df[, sample_cols, drop = FALSE])
    
    # Match samples between intensity matrix and coldata
    common_samples <- intersect(colnames(intensity_matrix), coldata\$sample)
    if (length(common_samples) == 0) {
      stop("No matching samples found between intensity.csv and coldata.csv")
    }
    
    intensity_matrix <- intensity_matrix[, common_samples, drop = FALSE]
    coldata <- coldata[match(common_samples, coldata\$sample), , drop = FALSE]
    
    # Identify control and treatment conditions dynamically
    conditions <- unique(coldata\$condition)
    control_cond <- grep("control|baseline|healthy|ctrl|ref|0|WT", conditions, ignore.case = TRUE, value = TRUE)
    if (length(control_cond) > 0) {
      control_cond <- control_cond[1]
    } else {
      control_cond <- conditions[1]
    }
    treat_cond <- setdiff(conditions, control_cond)
    if (length(treat_cond) > 0) {
      treat_cond <- treat_cond[1]
    } else {
      treat_cond <- control_cond
    }
    
    message("Control condition identified as: ", control_cond)
    message("Treatment condition identified as: ", treat_cond)
    
    # --- Estimate Negative Binomial parameters and Fold Changes ---
    markers <- rownames(intensity_matrix)
    n_markers <- length(markers)
    
    means <- numeric(n_markers)
    dispersions <- numeric(n_markers)
    fold_changes <- numeric(n_markers)
    subject_effects <- numeric(n_markers)
    
    # Check for donor/subject column to estimate subject effect
    donor_col <- grep("donor|subject|patient|pair|ind", colnames(coldata), ignore.case = TRUE, value = TRUE)
    has_donors <- length(donor_col) > 0
    
    for (i in seq_len(n_markers)) {
      marker <- markers[i]
      ctrl_vals <- intensity_matrix[marker, coldata\$condition == control_cond]
      treat_vals <- intensity_matrix[marker, coldata\$condition == treat_cond]
      
      # 1. Mean in control
      m_ctrl <- mean(ctrl_vals, na.rm = TRUE)
      means[i] <- m_ctrl
      
      # 2. Dispersion (size parameter of Negative Binomial)
      ctrl_counts <- round(ctrl_vals)
      ctrl_counts[ctrl_counts < 0] <- 0
      ctrl_counts <- ctrl_counts[!is.na(ctrl_counts)]
      
      if (length(unique(ctrl_counts)) <= 1 || all(ctrl_counts == 0)) {
        dispersions[i] <- 100 # Default low variance fallback
      } else {
        fit <- tryCatch({
          MASS::fitdistr(ctrl_counts, "negative binomial")
        }, error = function(e) NULL)
        
        if (!is.null(fit)) {
          dispersions[i] <- fit\$estimate[["size"]]
        } else {
          # Method of moments fallback
          v_ctrl <- var(ctrl_counts, na.rm = TRUE)
          if (!is.na(v_ctrl) && v_ctrl > m_ctrl) {
            dispersions[i] <- (m_ctrl^2) / (v_ctrl - m_ctrl)
          } else {
            dispersions[i] <- 100
          }
        }
      }
      
      # 3. Fold Change
      m_treat <- mean(treat_vals, na.rm = TRUE)
      fold_changes[i] <- if (m_ctrl > 0) m_treat / m_ctrl else 1
      
      # 4. Subject Effect (SD of donor means in control)
      if (has_donors) {
        ctrl_samples <- coldata\$sample[coldata\$condition == control_cond]
        ctrl_donors <- coldata[[donor_col[1]]][coldata\$condition == control_cond]
        donor_means <- tapply(intensity_matrix[marker, ctrl_samples], ctrl_donors, mean, na.rm = TRUE)
        subject_effects[i] <- sd(donor_means, na.rm = TRUE)
      } else {
        subject_effects[i] <- sd(ctrl_vals, na.rm = TRUE)
      }
    }
    
    # Global subject effect estimation
    global_subject_effect <- median(subject_effects, na.rm = TRUE)
    if (is.na(global_subject_effect) || global_subject_effect == 0) {
      global_subject_effect <- 0.1
    }
    
    # Save estimated parameters for CyTOFpower Shiny App
    param_df <- data.frame(
      marker = markers,
      mean = means,
      dispersion = dispersions,
      fold_change = fold_changes,
      stringsAsFactors = FALSE
    )
    write.csv(param_df, "personalized_parameters.csv", row.names = FALSE)
    message("Saved estimated parameters to 'personalized_parameters.csv'")
    
    # --- Run Offline Power Simulation ---
    n_donors <- if (has_donors) length(unique(coldata[[donor_col[1]]])) else sum(coldata\$condition == control_cond)
    if (n_donors < 3) {
      n_donors <- 5 # Minimum recommended donors for stable power estimation
    }
    
    n_cells <- 500
    n_sim <- 50
    
    message(sprintf("Running power simulation with %d donors, %d cells/sample, and %d simulations...", n_donors, n_cells, n_sim))
    
    p_values_matrix <- matrix(NA, nrow = n_markers, ncol = n_sim)
    rownames(p_values_matrix) <- markers
    
    for (sim in seq_len(n_sim)) {
      ctrl_sample_means <- matrix(NA, nrow = n_markers, ncol = n_donors)
      treat_sample_means <- matrix(NA, nrow = n_markers, ncol = n_donors)
      
      for (j in seq_len(n_markers)) {
        mu0 <- means[j]
        disp <- dispersions[j]
        fc <- fold_changes[j]
        
        if (mu0 <= 0) {
          ctrl_sample_means[j, ] <- 0
          treat_sample_means[j, ] <- 0
          next
        }
        
        # Derive Gamma parameters from mean and subject effect
        theta <- (global_subject_effect^2) / mu0
        k <- (mu0^2) / (global_subject_effect^2)
        
        for (i in seq_len(n_donors)) {
          # Draw donor-specific control mean
          mu_0_ij <- rgamma(1, shape = k, scale = theta)
          if (is.na(mu_0_ij) || mu_0_ij <= 0) mu_0_ij <- mu0
          
          # Draw donor-specific treatment mean
          mu_1_ij <- mu_0_ij * fc
          
          # Generate cell values using Negative Binomial
          cells_ctrl <- rnbinom(n_cells, mu = mu_0_ij, size = disp)
          ctrl_sample_means[j, i] <- mean(cells_ctrl)
          
          cells_treat <- rnbinom(n_cells, mu = mu_1_ij, size = disp)
          treat_sample_means[j, i] <- mean(cells_treat)
        }
      }
      
      # Compute p-values for each marker in this simulation
      for (j in seq_len(n_markers)) {
        if (means[j] <= 0) {
          p_values_matrix[j, sim] <- 1
          next
        }
        test_res <- tryCatch({
          t.test(ctrl_sample_means[j, ], treat_sample_means[j, ], paired = TRUE)
        }, error = function(e) NULL)
        
        if (!is.null(test_res)) {
          p_values_matrix[j, sim] <- test_res\$p.value
        } else {
          p_values_matrix[j, sim] <- 1
        }
      }
    }
    
    # Adjust p-values across markers for each simulation (FDR)
    adj_p_values_matrix <- apply(p_values_matrix, 2, p.adjust, method = "BH")
    
    # Calculate power (proportion of simulations with adjusted p-value < 0.05)
    power_results <- rowMeans(adj_p_values_matrix < 0.05, na.rm = TRUE)
    
    power_df <- data.frame(
      marker = markers,
      mean = means,
      dispersion = dispersions,
      fold_change = fold_changes,
      simulated_power = power_results,
      stringsAsFactors = FALSE
    )
    write.csv(power_df, "simulated_power_results.csv", row.names = FALSE)
    message("Saved simulated power results to 'simulated_power_results.csv'")
    
    # --- Generate Diagnostic and Power Report ---
    pdf("power_analysis_report.pdf", width = 8, height = 10)
    par(mfrow = c(3, 1), mar = c(5, 4, 4, 2) + 0.1)
    
    # Plot 1: Mean vs Dispersion
    plot(means, dispersions, log = "xy", pch = 19, col = "blue",
         xlab = "Mean (Control)", ylab = "Dispersion (Size Parameter)",
         main = "Marker Mean vs Dispersion (Log-Log Scale)")
    grid()
    
    # Plot 2: Distribution of Fold Changes
    hist(fold_changes, breaks = 20, col = "lightgreen", border = "white",
         xlab = "Fold Change (Treatment / Control)",
         main = "Distribution of Estimated Fold Changes")
    abline(v = 1, col = "red", lty = 2, lwd = 2)
    
    # Plot 3: Simulated Power per Marker
    plot_df <- power_df[order(-power_df\$simulated_power), ]
    if (nrow(plot_df) > 20) {
      plot_df <- plot_df[1:20, ]
      main_title <- "Simulated Power (Top 20 Markers)"
    } else {
      main_title <- "Simulated Power per Marker"
    }
    
    bp <- barplot(plot_df\$simulated_power, names.arg = plot_df\$marker,
                  col = ifelse(abs(plot_df\$fold_change - 1) < 0.05, "grey", "orange"),
                  las = 2, ylim = c(0, 1.1),
                  ylab = "Power (Rejection Rate at alpha=0.05)",
                  main = main_title)
    abline(h = 0.8, col = "red", lty = 2)
    text(bp, plot_df\$simulated_power + 0.05, round(plot_df\$simulated_power, 2), cex = 0.8, xpd = TRUE)
    
    dev.off()
    message("Saved diagnostic plots to 'power_analysis_report.pdf'")
    
    # Print instructions for launching the Shiny App
    cat("\n======================================================================\n")
    cat("CyTOFpower Analysis Pipeline Completed Successfully!\n")
    cat("======================================================================\n")
    cat("1. Estimated parameters saved to 'personalized_parameters.csv'.\n")
    cat("2. Offline simulated power results saved to 'simulated_power_results.csv'.\n")
    cat("3. Diagnostic and power plots saved to 'power_analysis_report.pdf'.\n\n")
    cat("To run the interactive CyTOFpower Shiny App and upload these parameters:\n")
    cat("  library(CyTOFpower)\n")
    cat("  CyTOFpower()\n")
    cat("Then, navigate to the 'Personalized dataset' tab and upload 'personalized_parameters.csv'.\n")
    cat("======================================================================\n")

    writeLines(c(
        '"BIOC_CYTOFPOWER_CYTOFPOWER_PARAMETER_ESTIMATION_AND_SIMULATION":',
        paste0('    CyTOFpower: ', as.character(packageVersion('CyTOFpower')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cytofpower_parameter_estimation_and_simulation.csv versions.yml
    """
}

workflow BIOC_CYTOFPOWER_CYTOFPOWER_PARAMETER_ESTIMATION_AND_SIMULATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_CYTOFPOWER_CYTOFPOWER_PARAMETER_ESTIMATION_AND_SIMULATION(ch_input)

    emit:
    tables   = BIOC_CYTOFPOWER_CYTOFPOWER_PARAMETER_ESTIMATION_AND_SIMULATION.out.tables
    plots    = BIOC_CYTOFPOWER_CYTOFPOWER_PARAMETER_ESTIMATION_AND_SIMULATION.out.plots
    objects  = BIOC_CYTOFPOWER_CYTOFPOWER_PARAMETER_ESTIMATION_AND_SIMULATION.out.objects
    versions = BIOC_CYTOFPOWER_CYTOFPOWER_PARAMETER_ESTIMATION_AND_SIMULATION.out.versions
}
