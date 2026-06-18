#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: sizepower — completely_randomized_design
// Calculate sample size and power for a completely randomized treatment-control design.
// Input: pilot_parameters.txt
// Container: quay.io/biocontainers/bioconductor-sizepower:1.80.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: sizepower
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Calculate required sample size using sampleSize.randomized
//  * 2. [Core Analysis] Calculate exact power for a given sample size using power.randomized

nextflow.enable.dsl = 2

process BIOC_SIZEPOWER_COMPLETELY_RANDOMIZED_DESIGN {
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
    if (!requireNamespace("sizepower", quietly = TRUE)) {
      stop("The 'sizepower' package is required but not installed.")
    }
    library(sizepower)
    
    # Read input parameters
    input_file <- "pilot_parameters.txt"
    if (!file.exists(input_file)) {
      stop(paste("Required input file", input_file, "not found in the working directory."))
    }
    
    # Parse parameters robustly (supports both key-value and standard table formats)
    lines <- readLines(input_file)
    lines <- trimws(lines)
    lines <- lines[lines != "" & !startsWith(lines, "#")]
    
    if (any(grepl("=", lines))) {
      # Key-value format (e.g., G0=2000)
      params <- list()
      for (line in lines) {
        parts <- strsplit(line, "=")[[1]]
        if (length(parts) == 2) {
          params[[trimws(parts[1])]] <- as.numeric(trimws(parts[2]))
        }
      }
      G0_val <- params\$G0
      ER0_val <- params\$ER0
      power_val <- params\$power
      absMu1_val <- params\$absMu1
      sigmad_val <- params\$sigmad
      n_val <- params\$n
    } else {
      # Table format with headers
      params <- read.table(input_file, header=TRUE, stringsAsFactors=FALSE)
      G0_val <- params\$G0[1]
      ER0_val <- params\$ER0[1]
      power_val <- params\$power[1]
      absMu1_val <- params\$absMu1[1]
      sigmad_val <- params\$sigmad[1]
      n_val <- params\$n[1]
    }
    
    # Validate parameters
    if (any(is.na(c(G0_val, ER0_val, power_val, absMu1_val, sigmad_val, n_val)))) {
      stop("One or more required parameters (G0, ER0, power, absMu1, sigmad, n) are missing or invalid in pilot_parameters.txt.")
    }
    
    # 1. Calculate required sample size using sampleSize.randomized
    size_res <- sampleSize.randomized(
      ER0 = ER0_val,
      G0 = G0_val,
      power = power_val,
      absMu1 = absMu1_val,
      sigmad = sigmad_val
    )
    
    # 2. Calculate exact power for a given sample size using power.randomized
    power_res <- power.randomized(
      ER0 = ER0_val,
      G0 = G0_val,
      absMu1 = absMu1_val,
      sigmad = sigmad_val,
      n = n_val
    )
    
    # Save results to CSV
    size_df <- data.frame(
      Parameter = c("Required_n", "Statistical_Distance_d"),
      Value = c(size_res\$n, size_res\$d)
    )
    write.csv(size_df, "sample_size_result.csv", row.names = FALSE)
    
    power_df <- data.frame(
      Parameter = c("Calculated_Power", "Non_Centrality_Psi1"),
      Value = c(power_res\$power, power_res\$psi1)
    )
    write.csv(power_df, "power_result.csv", row.names = FALSE)
    
    # Save RDS object
    results_list <- list(
      inputs = list(G0=G0_val, ER0=ER0_val, target_power=power_val, absMu1=absMu1_val, sigmad=sigmad_val, n_input=n_val),
      sample_size_calculation = size_res,
      power_calculation = power_res
    )
    saveRDS(results_list, "sizepower_results.rds")
    
    # Generate PDF plot
    pdf("power_vs_samplesize_plot.pdf", width=7, height=5)
    n_range <- seq(max(2, n_val - 5), n_val + 10)
    powers <- sapply(n_range, function(ni) {
      res <- power.randomized(
        ER0 = ER0_val,
        G0 = G0_val,
        absMu1 = absMu1_val,
        sigmad = sigmad_val,
        n = ni
      )
      res\$power
    })
    plot(n_range, powers, type="b", pch=19, col="blue",
         xlab="Sample Size per Group (n)", ylab="Power",
         main="Power vs Sample Size (Completely Randomized Design)")
    abline(h=power_val, col="red", lty=2)
    abline(v=size_res\$n, col="green", lty=2)
    legend("bottomright", legend=c("Power Curve", paste("Target Power (", power_val, ")", sep=""), paste("Required n (", size_res\$n, ")", sep="")),
           col=c("blue", "red", "green"), lty=c(1, 2, 2), pch=c(19, NA, NA))
    dev.off()
    
    cat("Pipeline completed successfully. Outputs written to sample_size_result.csv, power_result.csv, sizepower_results.rds, and power_vs_samplesize_plot.pdf\n")

    writeLines(c(
        '"BIOC_SIZEPOWER_COMPLETELY_RANDOMIZED_DESIGN":',
        paste0('    sizepower: ', as.character(packageVersion('sizepower')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_completely_randomized_design.csv versions.yml
    """
}

workflow BIOC_SIZEPOWER_COMPLETELY_RANDOMIZED_DESIGN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pilot_parameters.txt ] ]

    main:
    BIOC_SIZEPOWER_COMPLETELY_RANDOMIZED_DESIGN(ch_input)

    emit:
    tables   = BIOC_SIZEPOWER_COMPLETELY_RANDOMIZED_DESIGN.out.tables
    plots    = BIOC_SIZEPOWER_COMPLETELY_RANDOMIZED_DESIGN.out.plots
    objects  = BIOC_SIZEPOWER_COMPLETELY_RANDOMIZED_DESIGN.out.objects
    versions = BIOC_SIZEPOWER_COMPLETELY_RANDOMIZED_DESIGN.out.versions
}
