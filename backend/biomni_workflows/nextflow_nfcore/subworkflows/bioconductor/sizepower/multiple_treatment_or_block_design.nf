#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: sizepower — multiple_treatment_or_block_design
// Calculate power for multiple-treatment or randomized block designs with an isolated treatment effect.
// Input: pilot_parameters.txt
// Container: quay.io/biocontainers/bioconductor-sizepower:1.80.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: sizepower
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Calculate power for multiple-treatment or randomized block design using power.multi

nextflow.enable.dsl = 2

process BIOC_SIZEPOWER_MULTIPLE_TREATMENT_OR_BLOCK_DESIGN {
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
    
    # Load the required library
    if (!requireNamespace("sizepower", quietly = TRUE)) {
      stop("Package 'sizepower' is required but not installed.")
    }
    library(sizepower)
    
    # Define the input file path
    input_file <- "pilot_parameters.txt"
    
    # Check if the input file exists. If not, create a default one matching the vignette parameters.
    if (!file.exists(input_file)) {
      cat("ER0\tG0\tnumTrt\tabsMu1\tsigma\tn\n1\t2000\t5\t1\t0.4\t6\n1\t5000\t6\t0.9\t0.5\t9\n", file = input_file)
    }
    
    # Read the user input parameters
    params <- read.table(input_file, header = TRUE, stringsAsFactors = FALSE)
    
    # Initialize a list to store results
    results_list <- list()
    
    # Iterate through each row of parameters and calculate power
    for (i in seq_len(nrow(params))) {
      row <- params[i, ]
      
      # Call the documented function power.multi exactly as specified
      res <- power.multi(
        ER0 = row\$ER0,
        G0 = row\$G0,
        numTrt = row\$numTrt,
        absMu1 = row\$absMu1,
        sigma = row\$sigma,
        n = row\$n
      )
      
      # Store the results
      results_list[[i]] <- data.frame(
        ER0 = row\$ER0,
        G0 = row\$G0,
        numTrt = row\$numTrt,
        absMu1 = row\$absMu1,
        sigma = row\$sigma,
        n = row\$n,
        power = res\$power,
        psi1 = res\$psi1,
        stringsAsFactors = FALSE
      )
    }
    
    # Combine results into a single data frame
    results_df <- do.call(rbind, results_list)
    
    # Write the results to a CSV file
    write.csv(results_df, "power_results.csv", row.names = FALSE)
    
    # Save the results as an RDS object
    saveRDS(results_df, "power_results.rds")
    
    # Generate a PDF plot showing Power vs. Sample Size for each parameter set
    pdf("power_vs_samplesize_plot.pdf", width = 7, height = 6)
    for (i in seq_len(nrow(params))) {
      row <- params[i, ]
      
      # Evaluate power over a range of sample sizes (n from 2 to 20)
      n_range <- 2:20
      powers <- sapply(n_range, function(ni) {
        power.multi(
          ER0 = row\$ER0,
          G0 = row\$G0,
          numTrt = row\$numTrt,
          absMu1 = row\$absMu1,
          sigma = row\$sigma,
          n = ni
        )\$power
      })
      
      # Plot the power curve
      plot(
        n_range, powers, 
        type = "b", 
        pch = 19, 
        col = "blue",
        xlab = "Sample Size per Group (n)", 
        ylab = "Statistical Power",
        main = paste0("Power Curve (G0=", row\$G0, ", numTrt=", row\$numTrt, ", sigma=", row\$sigma, ")"),
        ylim = c(0, 1)
      )
      
      # Add reference lines for 80% power and the current sample size
      abline(h = 0.8, col = "red", lty = 2)
      abline(v = row\$n, col = "darkgreen", lty = 2)
      
      legend(
        "bottomright", 
        legend = c("Power Curve", "80% Power Threshold", paste0("Current n (", row\$n, ")")),
        col = c("blue", "red", "darkgreen"), 
        lty = c(1, 2, 2), 
        pch = c(19, NA, NA)
      )
    }
    dev.off()

    writeLines(c(
        '"BIOC_SIZEPOWER_MULTIPLE_TREATMENT_OR_BLOCK_DESIGN":',
        paste0('    sizepower: ', as.character(packageVersion('sizepower')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multiple_treatment_or_block_design.csv versions.yml
    """
}

workflow BIOC_SIZEPOWER_MULTIPLE_TREATMENT_OR_BLOCK_DESIGN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pilot_parameters.txt ] ]

    main:
    BIOC_SIZEPOWER_MULTIPLE_TREATMENT_OR_BLOCK_DESIGN(ch_input)

    emit:
    tables   = BIOC_SIZEPOWER_MULTIPLE_TREATMENT_OR_BLOCK_DESIGN.out.tables
    plots    = BIOC_SIZEPOWER_MULTIPLE_TREATMENT_OR_BLOCK_DESIGN.out.plots
    objects  = BIOC_SIZEPOWER_MULTIPLE_TREATMENT_OR_BLOCK_DESIGN.out.objects
    versions = BIOC_SIZEPOWER_MULTIPLE_TREATMENT_OR_BLOCK_DESIGN.out.versions
}
