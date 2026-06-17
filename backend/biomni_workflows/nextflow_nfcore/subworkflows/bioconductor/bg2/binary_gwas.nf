#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BG2 — binary_gwas
// Perform GWAS analysis on binary (Bernoulli) phenotypes using a two-step Bayesian GLMM with a kinship random effect.
// Input: Y_binary, SNPs, kinship
// Container: quay.io/biocontainers/bioconductor-bg2:1.10.0--r45hdfd78af_0
// R packages: BG2
// Bioconductor: 3.20 | R: 4.4
// Requires: BG2
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the binary phenotype, SNP, and kinship data
//  * 2. [Input & Preparation] Define the covariance matrix for the kinship random effect
//  * 3. [Core Analysis] Run the BG2 function with family="bernoulli", setting replicates to NULL and using an Inverse Gamma prior for Tau

nextflow.enable.dsl = 2

process BIOC_BG2_BINARY_GWAS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("BG2")
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
    library(BG2)
    
    # Helper function to read input files robustly from the working directory
    read_input <- function(base_name) {
      # Check for RDS
      if (file.exists(paste0(base_name, ".rds"))) {
        return(readRDS(paste0(base_name, ".rds")))
      }
      # Check for CSV
      if (file.exists(paste0(base_name, ".csv"))) {
        df <- read.csv(paste0(base_name, ".csv"), header = TRUE, check.names = FALSE)
        return(df)
      }
      # Check for TSV/TXT
      if (file.exists(paste0(base_name, ".txt"))) {
        df <- read.table(paste0(base_name, ".txt"), header = TRUE, check.names = FALSE)
        return(df)
      }
      # Check for exact filename
      if (file.exists(base_name)) {
        res <- try(readRDS(base_name), silent = TRUE)
        if (!inherits(res, "try-error")) return(res)
        res <- try(read.table(base_name, header = TRUE, check.names = FALSE), silent = TRUE)
        if (!inherits(res, "try-error")) return(res)
      }
      stop(paste("Error: Could not find or read input file for", base_name))
    }
    
    # 1. Load the binary phenotype, SNP, and kinship data
    Y_binary_raw <- read_input("Y_binary")
    if (is.data.frame(Y_binary_raw) || is.matrix(Y_binary_raw)) {
      Y_binary <- as.numeric(Y_binary_raw[[1]])
    } else {
      Y_binary <- as.numeric(Y_binary_raw)
    }
    
    SNPs_raw <- read_input("SNPs")
    SNPs <- as.matrix(SNPs_raw)
    
    kinship_raw <- read_input("kinship")
    kinship <- as.matrix(kinship_raw)
    
    # 2. Define the covariance matrix for the kinship random effect
    covariance <- list()
    covariance[[1]] <- kinship
    
    # 3. Run the BG2 function with family="bernoulli", setting replicates to NULL and using an Inverse Gamma prior for Tau
    set.seed(1330)
    output_binary <- BG2(Y=Y_binary, SNPs=SNPs, Fixed = NULL, 
                         Covariance=covariance, Z=NULL, family="bernoulli", 
                         replicates=NULL, Tau="IG",FDR_Nominal = 0.05, 
                         maxiterations = 4000, runs_til_stop = 400)
    
    # Print the output to console
    print(output_binary)
    
    # Write the meaningful results to output files
    saveRDS(output_binary, "output_binary.rds")
    
    # Create and save a summary table of selected SNPs
    selected_indices <- output_binary
    if (length(selected_indices) > 0) {
      snp_names <- colnames(SNPs)[selected_indices]
      results_df <- data.frame(
        Selected_Index = selected_indices,
        SNP_ID = if (is.null(snp_names)) paste0("SNP_", selected_indices) else snp_names
      )
    } else {
      results_df <- data.frame(
        Selected_Index = integer(0),
        SNP_ID = character(0)
      )
    }
    write.csv(results_df, "selected_snps.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_BG2_BINARY_GWAS":',
        paste0('    BG2: ', as.character(packageVersion('BG2')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_binary_gwas.csv versions.yml
    """
}

workflow BIOC_BG2_BINARY_GWAS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Y_binary, SNPs, kinship ] ]

    main:
    BIOC_BG2_BINARY_GWAS(ch_input)

    emit:
    tables   = BIOC_BG2_BINARY_GWAS.out.tables
    plots    = BIOC_BG2_BINARY_GWAS.out.plots
    objects  = BIOC_BG2_BINARY_GWAS.out.objects
    versions = BIOC_BG2_BINARY_GWAS.out.versions
}
