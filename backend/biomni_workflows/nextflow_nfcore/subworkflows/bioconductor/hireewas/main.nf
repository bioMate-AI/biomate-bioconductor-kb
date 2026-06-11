#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: HIREewas — hire_ewas_analysis
// Perform cell-type-specific association detection and deconvolution on bulk EWAS data.
// Input: Ometh, X
// Container: quay.io/biocontainers/bioconductor-hireewas:1.28.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: HIREewas
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the HIREewas package
//  * 2. [Core Analysis] Run the HIRE model using the bulk methylation matrix, covariate matrix, and specified number of cell types
//  * 3. [Core Analysis] Inspect estimated cell compositions, baseline profiles, phenotype effects, and p-values
//  * 4. [Visualization & Output] Visualize the detected cell-type-specific association patterns using riskCpGpattern

nextflow.enable.dsl = 2

process BIOC_HIREEWAS_HIRE_EWAS_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
        
        # Load the HIREewas package
        library(HIREewas)
        
        # Helper function to read input files robustly
        read_input <- function(base_name) {
          if (file.exists(paste0(base_name, ".rds"))) {
            return(readRDS(paste0(base_name, ".rds")))
          } else if (file.exists(paste0(base_name, ".csv"))) {
            return(as.matrix(read.csv(paste0(base_name, ".csv"), row.names = 1, check.names = FALSE)))
          } else if (file.exists(paste0(base_name, ".tsv"))) {
            return(as.matrix(read.delim(paste0(base_name, ".tsv"), row.names = 1, check.names = FALSE)))
          } else if (file.exists(base_name)) {
            return(as.matrix(read.csv(base_name, row.names = 1, check.names = FALSE)))
          } else {
            stop(paste("Required input file not found:", base_name))
          }
        }
        
        # Read user inputs from the working directory
        Ometh <- read_input("Ometh")
        X <- read_input("X")
        
        # Ensure inputs are numeric matrices
        Ometh <- as.matrix(Ometh)
        X <- as.matrix(X)
        
        # Determine the number of cell types (K)
        K <- 3
        if (file.exists("K.txt")) {
          K <- as.integer(readLines("K.txt", n = 1))
        }
        
        # Run the HIRE model using the bulk methylation matrix, covariate matrix, and specified number of cell types
        ret_list <- HIRE(Ometh, X, num_celltype=K, tol=10^(-5), num_iter=1000, alpha=0.01)
        
        # Inspect estimated cell compositions, baseline profiles, phenotype effects, and p-values
        class(ret_list)
        
        # Print summary of results to standard output
        cat("--- Estimated Cellular Compositions (First 6 samples) ---\n")
        print(ret_list\$P_t[ , 1:min(6, ncol(ret_list\$P_t))])
        
        cat("\n--- Estimated Cell-Type-Specific Methylation Baseline Profiles (Head) ---\n")
        print(head(ret_list\$mu_t))
        
        cat("\n--- Estimated Phenotype Effects (Head) ---\n")
        print(head(ret_list\$beta_t))
        
        cat("\n--- Penalized BIC Value ---\n")
        print(ret_list\$pBIC)
        
        cat("\n--- Estimated p-values for Phenotype 1 (Head, First 3 cell types) ---\n")
        print(head(ret_list\$pvalues[ , 1:min(3, ncol(ret_list\$pvalues))]))
        
        if (ncol(ret_list\$pvalues) >= (K + 3)) {
          cat("\n--- Estimated p-values for Phenotype 2 (Head, First 3 cell types) ---\n")
          print(head(ret_list\$pvalues[ , (K+1):min(K+3, ncol(ret_list\$pvalues))]))
        }
        
        # Visualize the detected cell-type-specific association patterns using riskCpGpattern
        pdf("riskCpGpattern_association.pdf", width = 8, height = 8)
        num_rows <- min(100, nrow(ret_list\$pvalues))
        if (nrow(X) >= 2 && ncol(ret_list\$pvalues) > K) {
          riskCpGpattern(ret_list\$pvalues[1:num_rows, (K+1):min(2*K, ncol(ret_list\$pvalues))], main_title="Detected association pattern\n with age", hc_row_ind = FALSE)
        } else {
          riskCpGpattern(ret_list\$pvalues[1:num_rows, 1:min(K, ncol(ret_list\$pvalues))], main_title="Detected association pattern", hc_row_ind = FALSE)
        }
        dev.off()
        
        # Write named output files for the meaningful results
        saveRDS(ret_list, "HIRE_results.rds")
        saveRDS(ret_list\$beta_t, "estimated_phenotype_effects.rds")
        write.csv(ret_list\$P_t, "estimated_cell_compositions.csv", row.names = TRUE)
        write.csv(ret_list\$mu_t, "estimated_baseline_profiles.csv", row.names = TRUE)
        write.csv(ret_list\$pvalues, "pvalues.csv", row.names = TRUE)
        writeLines(as.character(ret_list\$pBIC), "pBIC.txt")

    writeLines(c(
        '"BIOC_HIREEWAS_HIRE_EWAS_ANALYSIS":',
        paste0('    HIREewas: ', as.character(packageVersion('HIREewas')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hire_ewas_analysis.csv versions.yml
    """
}

workflow BIOC_HIREEWAS_HIRE_EWAS_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Ometh, X ] ]

    main:
    BIOC_HIREEWAS_HIRE_EWAS_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_HIREEWAS_HIRE_EWAS_ANALYSIS.out.tables
    plots    = BIOC_HIREEWAS_HIRE_EWAS_ANALYSIS.out.plots
    objects  = BIOC_HIREEWAS_HIRE_EWAS_ANALYSIS.out.objects
    versions = BIOC_HIREEWAS_HIRE_EWAS_ANALYSIS.out.versions
}
