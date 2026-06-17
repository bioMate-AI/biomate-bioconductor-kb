#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: microbiomeDASim — microbiome_da_simulation
// Simulate longitudinal differential microbiome abundance data parameterized by user-provided baseline abundance and metadata, and convert the simulated datasets 
// Input: abundance.csv, coldata.csv
// Container: 1.24.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ggplot2, microbiomeDASim
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MICROBIOMEDASIM_MICROBIOME_DA_SIMULATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metagenomics:3.20-deps"

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
    .bm_deps <- c("microbiomeDASim", "ggplot2")
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
    library(microbiomeDASim)
    library(ggplot2)
    
    # ==========================================
    # --- Input Processing & Parameter Estimation ---
    # ==========================================
    
    # Read user-provided input files
    if (!file.exists("abundance.csv") || !file.exists("coldata.csv")) {
      stop("Required input files 'abundance.csv' and/or 'coldata.csv' are missing.")
    }
    
    abundance <- read.csv("abundance.csv", row.names = 1, check.names = FALSE)
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    # Estimate baseline parameters from the input abundance matrix
    # We use log2-transformation to estimate parameters for the multivariate normal simulation
    log_abund <- log2(abundance + 1)
    control_mean <- mean(as.matrix(log_abund), na.rm = TRUE)
    if (is.na(control_mean) || is.infinite(control_mean)) {
      control_mean <- 2.0
    }
    
    sigma <- sd(as.matrix(log_abund), na.rm = TRUE)
    if (is.na(sigma) || sigma <= 0) {
      sigma <- 1.0
    }
    
    # Determine group sizes and structure from coldata
    group_col <- "group"
    if (!group_col %in% colnames(coldata)) {
      group_col <- colnames(coldata)[2] # Fallback to second column
    }
    
    # Identify control vs treatment samples
    control_idx <- grepl("control", coldata[[group_col]], ignore.case = TRUE)
    if (sum(control_idx) == 0) {
      # Fallback if no explicit "control" group is found
      control_idx <- seq_len(nrow(coldata)) <= (nrow(coldata) / 2)
    }
    
    n_control_samples <- sum(control_idx)
    n_treat_samples <- sum(!control_idx)
    
    # Define longitudinal design parameters
    # We assume a standard 4-timepoint longitudinal study design
    num_timepoints <- 4
    n_control <- max(2, ceiling(n_control_samples / num_timepoints))
    n_treat <- max(2, ceiling(n_treat_samples / num_timepoints))
    
    # Determine feature counts
    features <- nrow(abundance)
    if (features < 5) {
      features <- 10 # Ensure a reasonable number of features for simulation
    }
    diff_abun_features <- max(1, round(features * 0.2)) # 20% of features are DA
    
    # ==========================================
    # --- Single-Feature Longitudinal Simulation ---
    # ==========================================
    
    message("Simulating single-feature longitudinal trends...")
    
    # 1. Linear Trend Simulation
    sim_linear <- mvrnorm_sim(
      n_control = n_control,
      n_treat = n_treat,
      control_mean = control_mean,
      sigma = sigma,
      num_timepoints = num_timepoints,
      t_interval = c(0, num_timepoints - 1),
      rho = 0.8,
      corr_str = "ar1",
      func_form = "linear",
      beta = c(0.5, 1.5),
      missing_pct = 0.05,
      missing_per_subject = 1,
      dis_plot = FALSE
    )
    
    # 2. Hockey-Stick (L_up) Trend Simulation
    sim_hockey <- mvrnorm_sim(
      n_control = n_control,
      n_treat = n_treat,
      control_mean = control_mean,
      sigma = sigma,
      num_timepoints = num_timepoints,
      t_interval = c(0, num_timepoints - 1),
      rho = 0.8,
      corr_str = "ar1",
      func_form = "L_up",
      beta = 0.8,
      IP = 2,
      missing_pct = 0.05,
      missing_per_subject = 1,
      dis_plot = FALSE
    )
    
    # ==========================================
    # --- Multi-Feature Community Simulation ---
    # ==========================================
    
    message("Simulating multi-feature community data...")
    
    # Simulate a full microbiome community with specified proportion of DA features
    bug_gen <- gen_norm_microbiome(
      features = features,
      diff_abun_features = diff_abun_features,
      n_control = n_control,
      n_treat = n_treat,
      control_mean = control_mean,
      sigma = sigma,
      num_timepoints = num_timepoints,
      t_interval = c(0, num_timepoints - 1),
      rho = 0.7,
      corr_str = "compound",
      func_form = "M",
      beta = c(2.0, 1.5),
      IP = c(1, 2, 3),
      missing_pct = 0.1,
      missing_per_subject = 1,
      miss_val = 0
    )
    
    # ==========================================
    # --- Downstream Integration & Object Conversion ---
    # ==========================================
    
    message("Converting simulated datasets to Bioconductor objects...")
    
    # Convert to MRexperiment (metagenomeSeq)
    mre_obj <- tryCatch({
      simulate2MRexperiment(bug_gen)
    }, error = function(e) {
      warning("MRexperiment conversion failed: ", e\$message)
      NULL
    })
    
    # Convert to phyloseq
    phyloseq_obj <- tryCatch({
      simulate2phyloseq(bug_gen)
    }, error = function(e) {
      warning("Phyloseq conversion failed: ", e\$message)
      NULL
    })
    
    # ==========================================
    # --- Exporting Results & Visualizations ---
    # ==========================================
    
    message("Writing outputs to disk...")
    
    # Save simulated tables
    write.csv(bug_gen\$Y, "simulated_abundance.csv", row.names = TRUE)
    write.csv(bug_gen\$bug_feat, "simulated_metadata.csv", row.names = FALSE)
    
    # Save serialized Bioconductor objects if successfully created
    if (!is.null(mre_obj)) {
      saveRDS(mre_obj, "simulated_mre.rds")
    }
    if (!is.null(phyloseq_obj)) {
      saveRDS(phyloseq_obj, "simulated_phyloseq.rds")
    }
    
    # Generate and save diagnostic spaghetti plots
    pdf("simulated_trends.pdf", width = 8, height = 6)
    
    # Plot Linear Trend
    p1 <- tryCatch({
      ggplot_spaghetti(sim_linear\$df) + 
        ggtitle("Simulated Linear Trend (Single Feature)") +
        theme_bw()
    }, error = function(e) {
      ggplot(sim_linear\$df, aes(x = time, y = Y, group = ID, color = group)) +
        geom_line(alpha = 0.6) +
        geom_point() +
        stat_summary(aes(group = group), fun = mean, geom = "line", size = 1.5, linetype = "dashed") +
        ggtitle("Simulated Linear Trend (Fallback Plot)") +
        theme_bw()
    })
    print(p1)
    
    # Plot Hockey-Stick Trend
    p2 <- tryCatch({
      ggplot_spaghetti(sim_hockey\$df) + 
        ggtitle("Simulated Hockey-Stick Trend (Single Feature)") +
        theme_bw()
    }, error = function(e) {
      ggplot(sim_hockey\$df, aes(x = time, y = Y, group = ID, color = group)) +
        geom_line(alpha = 0.6) +
        geom_point() +
        stat_summary(aes(group = group), fun = mean, geom = "line", size = 1.5, linetype = "dashed") +
        ggtitle("Simulated Hockey-Stick Trend (Fallback Plot)") +
        theme_bw()
    })
    print(p2)
    
    dev.off()
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_MICROBIOMEDASIM_MICROBIOME_DA_SIMULATION":',
        paste0('    microbiomeDASim: ', as.character(packageVersion('microbiomeDASim')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_microbiome_da_simulation.csv versions.yml
    """
}

workflow BIOC_MICROBIOMEDASIM_MICROBIOME_DA_SIMULATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_MICROBIOMEDASIM_MICROBIOME_DA_SIMULATION(ch_input)

    emit:
    tables   = BIOC_MICROBIOMEDASIM_MICROBIOME_DA_SIMULATION.out.tables
    plots    = BIOC_MICROBIOMEDASIM_MICROBIOME_DA_SIMULATION.out.plots
    objects  = BIOC_MICROBIOMEDASIM_MICROBIOME_DA_SIMULATION.out.objects
    versions = BIOC_MICROBIOMEDASIM_MICROBIOME_DA_SIMULATION.out.versions
}
