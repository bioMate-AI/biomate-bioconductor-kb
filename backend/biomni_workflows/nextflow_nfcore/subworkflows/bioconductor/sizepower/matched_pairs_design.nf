#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: sizepower — matched_pairs_design
// Calculate sample size and power for a matched-pairs design.
// Input: pilot_parameters.txt
// Container: quay.io/biocontainers/bioconductor-sizepower:1.80.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: sizepower
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Calculate required sample size using sampleSize.matched
//  * 2. [Core Analysis] Calculate exact power for a given sample size using power.matched

nextflow.enable.dsl = 2

process BIOC_SIZEPOWER_MATCHED_PAIRS_DESIGN {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("sizepower")
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
    
    # Load required library
    library(sizepower)
    
    # Read user input file
    input_file <- "pilot_parameters.txt"
    if (!file.exists(input_file)) {
      stop(paste("Error: Input file", input_file, "not found in the working directory."))
    }
    
    params_df <- read.table(input_file, header = TRUE, stringsAsFactors = FALSE)
    
    # Parse parameters robustly (handles both key-value format and single-row table format)
    if ("parameter" %in% colnames(params_df) && "value" %in% colnames(params_df)) {
      params <- setNames(as.numeric(params_df\$value), params_df\$parameter)
      G0 <- params["G0"]
      ER0 <- params["ER0"]
      power_val <- params["power"]
      absMu1 <- params["absMu1"]
      sigmad <- params["sigmad"]
      n_val <- params["n"]
    } else {
      G0 <- as.numeric(params_df\$G0[1])
      ER0 <- as.numeric(params_df\$ER0[1])
      power_val <- as.numeric(params_df\$power[1])
      absMu1 <- as.numeric(params_df\$absMu1[1])
      sigmad <- as.numeric(params_df\$sigmad[1])
      n_val <- as.numeric(params_df\$n[1])
    }
    
    # Validate parameters
    if (any(is.na(c(G0, ER0, power_val, absMu1, sigmad, n_val)))) {
      stop("Error: One or more required parameters (G0, ER0, power, absMu1, sigmad, n) are missing or invalid in pilot_parameters.txt")
    }
    
    # 1. Calculate required sample size using sampleSize.matched
    ss_res <- sampleSize.matched(ER0=ER0, G0=G0, power=power_val, absMu1=absMu1, sigmad=sigmad)
    
    # 2. Calculate exact power for a given sample size using power.matched
    pow_res <- power.matched(ER0=ER0, G0=G0, absMu1=absMu1, sigmad=sigmad, n=n_val)
    
    # Convert results to data frames for saving
    ss_df <- data.frame(
      Parameter = c("Required_n", "Statistical_Distance_d"),
      Value = c(ss_res\$n, ss_res\$d)
    )
    
    pow_df <- data.frame(
      Parameter = c("Calculated_Power", "Non_Centrality_Parameter_psi1"),
      Value = c(pow_res\$power, pow_res\$psi1)
    )
    
    # Write CSV outputs
    write.csv(ss_df, "sample_size_result.csv", row.names = FALSE)
    write.csv(pow_df, "power_result.csv", row.names = FALSE)
    
    # Generate a power curve for a range of sample sizes (e.g., from 2 to 20)
    n_range <- 2:20
    power_curve <- sapply(n_range, function(ni) {
      res <- power.matched(ER0=ER0, G0=G0, absMu1=absMu1, sigmad=sigmad, n=ni)
      return(res\$power)
    })
    
    curve_df <- data.frame(
      Sample_Size = n_range,
      Power = power_curve
    )
    write.csv(curve_df, "power_curve.csv", row.names = FALSE)
    
    # Plot the power curve and save as PDF
    pdf("power_vs_samplesize_plot.pdf", width = 7, height = 5)
    plot(curve_df\$Sample_Size, curve_df\$Power, type = "b", pch = 19, col = "blue",
         xlab = "Sample Size (n per group)", ylab = "Power",
         main = "Power vs. Sample Size (Matched-Pairs Design)")
    abline(h = power_val, col = "red", lty = 2)
    abline(v = ss_res\$n, col = "green", lty = 2)
    legend("bottomright", legend = c("Power Curve", "Target Power", "Required Sample Size"),
           col = c("blue", "red", "green"), lty = c(1, 2, 2), pch = c(19, NA, NA))
    dev.off()
    
    # Save RDS object containing all results
    results_list <- list(
      inputs = list(G0 = G0, ER0 = ER0, target_power = power_val, absMu1 = absMu1, sigmad = sigmad, n_input = n_val),
      sample_size_calculation = ss_res,
      power_calculation = pow_res,
      power_curve = curve_df
    )
    saveRDS(results_list, "sizepower_results.rds")
    
    cat("Pipeline completed successfully. Outputs saved:\n")
    cat("- sample_size_result.csv\n")
    cat("- power_result.csv\n")
    cat("- power_curve.csv\n")
    cat("- power_vs_samplesize_plot.pdf\n")
    cat("- sizepower_results.rds\n")

    writeLines(c(
        '"BIOC_SIZEPOWER_MATCHED_PAIRS_DESIGN":',
        paste0('    sizepower: ', as.character(packageVersion('sizepower')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_matched_pairs_design.csv versions.yml
    """
}

workflow BIOC_SIZEPOWER_MATCHED_PAIRS_DESIGN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pilot_parameters.txt ] ]

    main:
    BIOC_SIZEPOWER_MATCHED_PAIRS_DESIGN(ch_input)

    emit:
    tables   = BIOC_SIZEPOWER_MATCHED_PAIRS_DESIGN.out.tables
    plots    = BIOC_SIZEPOWER_MATCHED_PAIRS_DESIGN.out.plots
    objects  = BIOC_SIZEPOWER_MATCHED_PAIRS_DESIGN.out.objects
    versions = BIOC_SIZEPOWER_MATCHED_PAIRS_DESIGN.out.versions
}
