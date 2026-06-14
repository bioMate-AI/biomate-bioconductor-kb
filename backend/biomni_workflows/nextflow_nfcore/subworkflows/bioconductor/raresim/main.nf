#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RAREsim — estimate_expected_variants_from_target_data
// Estimate the expected number of rare variants per MAC bin by fitting model parameters to user-provided target population data.
// Input: nvariant_target.csv, afs_target.csv
// Container: quay.io/biocontainers/bioconductor-raresim:1.14.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: RAREsim, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] User Parameters & Input Files
//  * 2. [Core Analysis] Fit Number of Variants Function
//  * 3. [Core Analysis] Calculate Expected Variants per Kb
//  * 4. [Core Analysis] Scale Variants by Region Size
//  * 5. [Core Analysis] Fit Allele Frequency Spectrum (AFS)
//  * 6. [Core Analysis] Combine to Get Expected Variants per MAC Bin

nextflow.enable.dsl = 2

process BIOC_RARESIM_ESTIMATE_EXPECTED_VARIANTS_FROM_TARGET_DATA {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20"

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
    .bm_deps <- c("RAREsim", "ggplot2")
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
    library(RAREsim)
    library(ggplot2)
    
    # ==========================================
    # --- User Parameters & Input Files ---
    # ==========================================
    # Define target simulation parameters
    target_N <- 8128          # Target simulation sample size
    region_size_kb <- 19.029  # Region size in Kb
    
    # The pipeline reads exactly these files from the working directory
    nvariant_target <- read.csv("nvariant_target.csv", stringsAsFactors = FALSE)
    afs_target <- read.csv("afs_target.csv", stringsAsFactors = FALSE)
    
    # ==========================================
    # --- Fit Number of Variants Function ---
    # ==========================================
    # Fit the number of variants function to target data to estimate phi and omega
    nvar <- fit_nvariant(nvariant_target)
    
    # Save fitted parameters
    saveRDS(nvar, file = "nvariant_fit_parameters.rds")
    
    # Plot the fit of the number of variants function
    pdf("nvariant_fit_plot.pdf", width = 6, height = 6)
    plot(nvariant_target\$n, nvariant_target\$per_kb, 
         xlab = 'Sample Size', ylab = 'Variants per Kb',
         main = "Number of Variants Function Fit")
    lines(nvariant_target\$n, (nvar\$phi * (nvariant_target\$n ^ nvar\$omega)), col = "blue", lwd = 2)
    dev.off()
    
    # ==========================================
    # --- Calculate Expected Variants per Kb ---
    # ==========================================
    # Calculate the expected number of variants per Kb for the target simulation sample size
    expected_per_kb <- nvariant(phi = nvar\$phi, omega = nvar\$omega, N = target_N)
    
    # ==========================================
    # --- Scale Variants by Region Size ---
    # ==========================================
    # Scale the variants per Kb by the region size to get the total expected number of variants
    total_expected_var <- region_size_kb * expected_per_kb
    
    # ==========================================
    # --- Fit Allele Frequency Spectrum (AFS) ---
    # ==========================================
    # Fit the AFS function to target data to estimate alpha, beta, and b
    af <- fit_afs(Observed_bin_props = afs_target)
    
    # Save fitted AFS parameters
    saveRDS(af, file = "afs_fit_parameters.rds")
    
    # Extract MAC bins
    mac <- afs_target[, c(1:2)]
    
    # Plot the AFS fit
    afs_target\$Data <- 'Target Data'
    af\$Fitted_results\$Data <- 'Fitted Function'
    af_all <- rbind(afs_target, af\$Fitted_results)
    af_all\$Data <- as.factor(af_all\$Data)
    
    p <- ggplot(data = af_all) +
      geom_point(mapping = aes(x = Lower, y = Prop, col = Data), size = 3) +
      labs(x = 'Lower Limit of MAC Bin', y = 'Proportion of Variants', title = "AFS Function Fit") +
      theme_minimal()
    
    ggsave("afs_fit_plot.pdf", plot = p, width = 7, height = 5)
    
    # ==========================================
    # --- Combine to Get Expected Variants per MAC Bin ---
    # ==========================================
    # Combine the total expected variants and the fitted AFS proportions to get expected variants per MAC bin
    bin_estimates <- expected_variants(Total_num_var = total_expected_var, mac_bin_prop = af\$Fitted_results)
    
    # Save the final expected variants per MAC bin
    write.csv(bin_estimates, file = "expected_variants_per_mac_bin.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_RARESIM_ESTIMATE_EXPECTED_VARIANTS_FROM_TARGET_DATA":',
        paste0('    RAREsim: ', as.character(packageVersion('RAREsim')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_estimate_expected_variants_from_target_data.csv versions.yml
    """
}

workflow BIOC_RARESIM_ESTIMATE_EXPECTED_VARIANTS_FROM_TARGET_DATA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ nvariant_target.csv, afs_target.csv ] ]

    main:
    BIOC_RARESIM_ESTIMATE_EXPECTED_VARIANTS_FROM_TARGET_DATA(ch_input)

    emit:
    tables   = BIOC_RARESIM_ESTIMATE_EXPECTED_VARIANTS_FROM_TARGET_DATA.out.tables
    plots    = BIOC_RARESIM_ESTIMATE_EXPECTED_VARIANTS_FROM_TARGET_DATA.out.plots
    objects  = BIOC_RARESIM_ESTIMATE_EXPECTED_VARIANTS_FROM_TARGET_DATA.out.objects
    versions = BIOC_RARESIM_ESTIMATE_EXPECTED_VARIANTS_FROM_TARGET_DATA.out.versions
}
