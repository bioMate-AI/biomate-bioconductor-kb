#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: miaSim — miasim_microbiome_simulation
// Simulate and compare multiple ecological dynamics models (gLV, Ricker, SOI, Consumer-Resource, Hubbell, and Stochastic Logistic) parameterized using input speci
// Input: matrix.csv, coldata.csv
// Container: 1.16.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, miaSim
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MIASIM_MIASIM_MICROBIOME_SIMULATION {
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("miaSim")
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
    library(miaSim)
    
    # ==========================================
    # --- Load and Preprocess Input Data ---
    # ==========================================
    if (!file.exists("matrix.csv") || !file.exists("coldata.csv")) {
      stop("Required input files 'matrix.csv' or 'coldata.csv' not found.")
    }
    
    # Read feature-by-sample matrix
    mat_df <- read.csv("matrix.csv", check.names = FALSE)
    if (!"feature_id" %in% colnames(mat_df)) {
      stop("matrix.csv must contain a 'feature_id' column.")
    }
    rownames(mat_df) <- mat_df\$feature_id
    mat_df\$feature_id <- NULL
    mat <- as.matrix(mat_df)
    
    # Read sample metadata
    coldata <- read.csv("coldata.csv", check.names = FALSE)
    
    # Filter to top species to ensure simulation stability and speed
    # (Simulating too many species with random/powerlaw interactions can easily diverge or become unstable)
    top_n <- min(10, nrow(mat))
    species_means <- rowMeans(mat, na.rm = TRUE)
    top_species <- names(sort(species_means, decreasing = TRUE)[1:top_n])
    mat_filtered <- mat[top_species, , drop = FALSE]
    n_species <- nrow(mat_filtered)
    
    # Estimate initial abundances (x0) from the mean of the input data
    x0 <- rowMeans(mat_filtered, na.rm = TRUE)
    # Ensure x0 is strictly positive for models requiring non-zero initial states
    x0[x0 <= 0] <- 0.1
    
    # ==========================================
    # --- Generate Interaction & Resource Matrices ---
    # ==========================================
    message("Generating interaction matrices...")
    # Generate interactions from power-law distribution
    A_powerlaw <- powerlawA(n_species = n_species, alpha = 3)
    
    # Generate interactions from uniform distribution
    A_random <- randomA(n_species = n_species, diagonal = -0.4, connectance = 0.5)
    
    # Generate production/consumption matrix for Consumer-Resource model
    E_matrix <- randomE(n_species = n_species, n_resources = n_species * 2)
    
    # ==========================================
    # --- Run Simulation Models ---
    # ==========================================
    message("Running simulations...")
    
    # 3.1 Generalized Lotka-Volterra (gLV)
    tse_glv <- tryCatch({
      simulateGLV(n_species = n_species, A = A_powerlaw, t_start = 0, t_store = 100, stochastic = FALSE, norm = TRUE)
    }, error = function(e) {
      warning("gLV simulation failed: ", e\$message)
      NULL
    })
    
    # 3.2 Ricker Model (Discrete version of gLV)
    tse_ricker <- tryCatch({
      simulateRicker(n_species = n_species, A = A_powerlaw, t_end = 100, norm = TRUE)
    }, error = function(e) {
      warning("Ricker simulation failed: ", e\$message)
      NULL
    })
    
    # 3.3 Self-Organized Instability (SOI) Model
    tse_soi <- tryCatch({
      simulateSOI(n_species = n_species, carrying_capacity = 1000, A = A_powerlaw, k_events = 5, x0 = x0, t_end = 100, norm = TRUE)
    }, error = function(e) {
      warning("SOI simulation failed: ", e\$message)
      NULL
    })
    
    # 3.4 Consumer-Resource Model
    tse_crm <- tryCatch({
      simulateConsumerResource(n_species = n_species, n_resources = n_species * 2, E = E_matrix)
    }, error = function(e) {
      warning("Consumer-Resource simulation failed: ", e\$message)
      NULL
    })
    
    # 3.5 Hubbell Neutral Model
    tse_hubbell <- tryCatch({
      simulateHubbell(n_species = n_species, M = 10, carrying_capacity = 1000, k_events = 50, migration_p = 0.02, t_end = 100)
    }, error = function(e) {
      warning("Hubbell simulation failed: ", e\$message)
      NULL
    })
    
    # 3.6 Stochastic Logistic Model
    tse_logistic <- tryCatch({
      simulateStochasticLogistic(n_species = n_species)
    }, error = function(e) {
      warning("Stochastic Logistic simulation failed: ", e\$message)
      NULL
    })
    
    # ==========================================
    # --- Export Simulated Abundance Matrices ---
    # ==========================================
    write_simulation_csv <- function(tse, filename) {
      if (!is.null(tse)) {
        counts <- assay(tse, "counts")
        times <- colData(tse)\$time
        if (!is.null(times)) {
          colnames(counts) <- paste0("Time_", round(times, 2))
        } else {
          colnames(counts) <- paste0("Step_", seq_len(ncol(counts)))
        }
        write.csv(as.data.frame(counts), filename, row.names = TRUE)
      } else {
        write.csv(data.frame(Status = "Simulation Failed"), filename, row.names = FALSE)
      }
    }
    
    write_simulation_csv(tse_glv, "glv_simulation.csv")
    write_simulation_csv(tse_ricker, "ricker_simulation.csv")
    write_simulation_csv(tse_soi, "soi_simulation.csv")
    write_simulation_csv(tse_crm, "crm_simulation.csv")
    write_simulation_csv(tse_hubbell, "hubbell_simulation.csv")
    write_simulation_csv(tse_logistic, "logistic_simulation.csv")
    
    # ==========================================
    # --- Visualization of Trajectories ---
    # ==========================================
    pdf("simulation_plots.pdf", width = 10, height = 8)
    par(mfrow = c(3, 2), mar = c(4, 4, 3, 1))
    
    plot_trajectory <- function(tse, title) {
      if (is.null(tse)) {
        plot(1, type = "n", axes = FALSE, xlab = "", ylab = "", main = paste(title, "(Failed)"))
        text(1, 1, "Simulation Failed", cex = 1.2)
        return()
      }
      counts <- assay(tse, "counts")
      times <- colData(tse)\$time
      if (is.null(times)) {
        times <- seq_len(ncol(counts))
      }
      
      # Plot trajectories of simulated species
      plot(times, counts[1, ], type = "l", ylim = range(counts, na.rm = TRUE),
           xlab = "Time", ylab = "Abundance", main = title, col = 1, lwd = 1.5)
      if (nrow(counts) > 1) {
        for (i in 2:nrow(counts)) {
          lines(times, counts[i, ], col = i, lwd = 1.5)
        }
      }
      legend("topright", legend = paste0("Sp_", seq_len(nrow(counts))), 
             col = seq_len(nrow(counts)), lty = 1, cex = 0.6, bty = "n")
    }
    
    plot_trajectory(tse_glv, "Generalized Lotka-Volterra (gLV)")
    plot_trajectory(tse_ricker, "Ricker Model")
    plot_trajectory(tse_soi, "Self-Organized Instability (SOI)")
    plot_trajectory(tse_crm, "Consumer-Resource Model")
    plot_trajectory(tse_hubbell, "Hubbell Neutral Model")
    plot_trajectory(tse_logistic, "Stochastic Logistic Model")
    
    dev.off()
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_MIASIM_MIASIM_MICROBIOME_SIMULATION":',
        paste0('    miaSim: ', as.character(packageVersion('miaSim')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_miasim_microbiome_simulation.csv versions.yml
    """
}

workflow BIOC_MIASIM_MIASIM_MICROBIOME_SIMULATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_MIASIM_MIASIM_MICROBIOME_SIMULATION(ch_input)

    emit:
    tables   = BIOC_MIASIM_MIASIM_MICROBIOME_SIMULATION.out.tables
    plots    = BIOC_MIASIM_MIASIM_MICROBIOME_SIMULATION.out.plots
    objects  = BIOC_MIASIM_MIASIM_MICROBIOME_SIMULATION.out.objects
    versions = BIOC_MIASIM_MIASIM_MICROBIOME_SIMULATION.out.versions
}
