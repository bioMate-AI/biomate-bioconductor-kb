#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BG2 — poisson_gwas
// Perform GWAS analysis on Poisson-distributed count phenotypes using a two-step Bayesian GLMM with kinship and overdispersion random effects.
// Input: Y_poisson, SNPs, kinship
// Container: quay.io/biocontainers/bioconductor-bg2:1.10.0--r45hdfd78af_0
// R packages: BG2
// Bioconductor: 3.20 | R: 4.4
// Requires: BG2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the phenotype, SNP, and kinship data
//  * 2. [Input & Preparation] Define the covariance matrices for the random effects (kinship and identity matrix for overdispersion)
//  * 3. [Core Analysis] Run the BG2 function with family="poisson", specifying the number of replicates and a uniform prior for Tau

nextflow.enable.dsl = 2

process BIOC_BG2_POISSON_GWAS {
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
    
    # Helper function to robustly load user input files from the working directory
    load_data <- function(base_name) {
      extensions <- c(".rds", ".csv", ".tsv", ".txt")
      for (ext in extensions) {
        file_path <- paste0(base_name, ext)
        if (file.exists(file_path)) {
          message("Loading ", file_path)
          if (ext == ".rds") {
            return(readRDS(file_path))
          } else if (ext == ".csv") {
            if (base_name == "Y_poisson") {
              df <- read.csv(file_path, header = FALSE)
              if (!is.numeric(df[1, 1])) {
                df <- read.csv(file_path, header = TRUE)
              }
              return(as.numeric(df[[1]]))
            } else {
              return(as.matrix(read.csv(file_path, header = TRUE, row.names = 1, check.names = FALSE)))
            }
          } else if (ext == ".tsv" || ext == ".txt") {
            sep <- if (ext == ".tsv") "\t" else ""
            if (base_name == "Y_poisson") {
              df <- read.table(file_path, header = FALSE, sep = sep)
              if (!is.numeric(df[1, 1])) {
                df <- read.table(file_path, header = TRUE, sep = sep)
              }
              return(as.numeric(df[[1]]))
            } else {
              return(as.matrix(read.table(file_path, header = TRUE, row.names = 1, sep = sep, check.names = FALSE)))
            }
          }
        }
      }
      stop(paste("Error: Could not find file for", base_name, "with supported extensions (.rds, .csv, .tsv, .txt)"))
    }
    
    # 1. Load the phenotype, SNP, and kinship data
    Y_poisson <- load_data("Y_poisson")
    SNPs <- load_data("SNPs")
    kinship <- load_data("kinship")
    
    # 2. Define the covariance matrices for the random effects (kinship and identity matrix for overdispersion)
    n <- length(Y_poisson)
    covariance <- list()
    covariance[[1]] <- kinship
    covariance[[2]] <- diag(1, nrow = n, ncol = n)
    
    # 3. Run the BG2 function with family="poisson", specifying the number of replicates and a uniform prior for Tau
    set.seed(1330)
    output_poisson <- BG2(Y=Y_poisson, SNPs=SNPs, Fixed = NULL, 
                          Covariance=covariance, Z=NULL, family="poisson", 
                          replicates=4, Tau="uniform",FDR_Nominal = 0.05, 
                          maxiterations = 4000, runs_til_stop = 400)
    
    # Print output to console
    print(output_poisson)
    
    # Save meaningful results to output files
    saveRDS(output_poisson, "output_poisson.rds")
    
    # Create a CSV table of selected SNPs
    selected_indices <- output_poisson
    selected_names <- colnames(SNPs)[selected_indices]
    results_df <- data.frame(
      Index = selected_indices,
      SNP_Name = if (is.null(selected_names)) NA else selected_names
    )
    write.csv(results_df, "selected_snps.csv", row.names = FALSE)
    
    # Generate a PDF plot summarizing the results
    pdf("poisson_gwas_summary.pdf", width = 8, height = 6)
    par(mfrow = c(2, 1))
    
    # Plot 1: Phenotype distribution
    hist(Y_poisson, main = "Distribution of Poisson Phenotype", xlab = "Y_poisson", col = "skyblue", border = "white")
    
    # Plot 2: Selected SNPs across the genome/index space
    plot(1:ncol(SNPs), rep(0, ncol(SNPs)), type = "n", yaxt = "n", xlab = "SNP Index", ylab = "", main = "Selected SNPs (marked in red)")
    abline(h = 0, col = "gray")
    if (length(output_poisson) > 0) {
      points(output_poisson, rep(0, length(output_poisson)), col = "red", pch = 19, cex = 1.5)
      if (!is.null(selected_names)) {
        text(output_poisson, rep(0.1, length(output_poisson)), labels = selected_names, col = "red", pos = 3, cex = 0.8)
      }
    }
    dev.off()
    
    message("Pipeline completed successfully. Outputs saved to 'output_poisson.rds', 'selected_snps.csv', and 'poisson_gwas_summary.pdf'.")

    writeLines(c(
        '"BIOC_BG2_POISSON_GWAS":',
        paste0('    BG2: ', as.character(packageVersion('BG2')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_poisson_gwas.csv versions.yml
    """
}

workflow BIOC_BG2_POISSON_GWAS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Y_poisson, SNPs, kinship ] ]

    main:
    BIOC_BG2_POISSON_GWAS(ch_input)

    emit:
    tables   = BIOC_BG2_POISSON_GWAS.out.tables
    plots    = BIOC_BG2_POISSON_GWAS.out.plots
    objects  = BIOC_BG2_POISSON_GWAS.out.objects
    versions = BIOC_BG2_POISSON_GWAS.out.versions
}
