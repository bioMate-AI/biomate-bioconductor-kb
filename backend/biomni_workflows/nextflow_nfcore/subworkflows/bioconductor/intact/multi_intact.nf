#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: INTACT — multi_intact
// Jointly integrate GWAS results and QTL data for two molecular gene products to compute gene probabilities of putative causality (GPPCs) and gene product relevan
// Input: z_sumstats, exprwt_sumstats, protwt_sumstats, ld_sumstats, multi_simdat
// Container: quay.io/biocontainers/bioconductor-intact:1.10.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: INTACT, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read User Inputs
//  * 2. [Visualization & Output] Estimate the Chi-square Statistic From Summary-level Data
//  * 3. [Visualization & Output] Run Multi-INTACT (Standard Workflow)
//  * 4. [Visualization & Output] Run Multi-INTACT with Model Posteriors
//  * 5. [Visualization & Output] Run Multi-INTACT without EM Algorithm
//  * 6. [Visualization & Output] Visualization of Results

nextflow.enable.dsl = 2

process BIOC_INTACT_MULTI_INTACT {
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
    .bm_deps <- c("INTACT", "ggplot2")
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
    library(INTACT)
    library(ggplot2)
    
    # Helper function to robustly read input files (RDS or CSV) from the working directory
    read_input <- function(base_name) {
      rds_path <- paste0(base_name, ".rds")
      csv_path <- paste0(base_name, ".csv")
      tsv_path <- paste0(base_name, ".tsv")
      
      if (file.exists(rds_path)) {
        return(readRDS(rds_path))
      } else if (file.exists(csv_path)) {
        df <- read.csv(csv_path, header = TRUE, row.names = NULL, check.names = FALSE)
        # If there is an empty or "X" first column that looks like row names, set them
        if (ncol(df) > 1 && (is.character(df[[1]]) || is.factor(df[[1]])) && any(duplicated(df[[1]])) == FALSE) {
          rownames(df) <- df[[1]]
          df <- df[-1]
        }
        return(df)
      } else if (file.exists(tsv_path)) {
        df <- read.delim(tsv_path, header = TRUE, row.names = NULL, check.names = FALSE)
        if (ncol(df) > 1 && (is.character(df[[1]]) || is.factor(df[[1]])) && any(duplicated(df[[1]])) == FALSE) {
          rownames(df) <- df[[1]]
          df <- df[-1]
        }
        return(df)
      } else if (file.exists(base_name)) {
        # Try reading the file directly if no extension was appended but file exists
        tryCatch({
          return(readRDS(base_name))
        }, error = function(e) {
          return(read.csv(base_name, header = TRUE, check.names = FALSE))
        })
      } else {
        stop(paste("Required input file not found in working directory:", base_name))
      }
    }
    
    # Helper to convert data frames to vectors or matrices as required by INTACT functions
    to_vector_or_matrix <- function(obj) {
      if (is.data.frame(obj)) {
        if (ncol(obj) == 1) {
          val <- obj[[1]]
          if (!is.null(rownames(obj))) {
            names(val) <- rownames(obj)
          }
          return(val)
        } else {
          return(as.matrix(obj))
        }
      }
      return(obj)
    }
    
    # -----------------------------------------------------------------------------
    # --- Read User Inputs ---
    # -----------------------------------------------------------------------------
    message("Reading input files...")
    
    z_sumstats_raw       <- read_input("z_sumstats")
    exprwt_sumstats_raw  <- read_input("exprwt_sumstats")
    protwt_sumstats_raw  <- read_input("protwt_sumstats")
    ld_sumstats_raw      <- read_input("ld_sumstats")
    multi_simdat         <- read_input("multi_simdat")
    
    # Format inputs appropriately for the INTACT package
    z_sumstats       <- to_vector_or_matrix(z_sumstats_raw)
    exprwt_sumstats  <- to_vector_or_matrix(exprwt_sumstats_raw)
    protwt_sumstats  <- to_vector_or_matrix(protwt_sumstats_raw)
    ld_sumstats      <- to_vector_or_matrix(ld_sumstats_raw)
    
    # Ensure multi_simdat is a data frame
    multi_simdat <- as.data.frame(multi_simdat)
    
    # -----------------------------------------------------------------------------
    # --- Estimate the Chi-square Statistic From Summary-level Data ---
    # -----------------------------------------------------------------------------
    message("Estimating multivariate Wald chi-square statistic...")
    
    chisq_val <- INTACT::chisq_sumstat(
      z_vec = z_sumstats, 
      w = cbind(protwt_sumstats, exprwt_sumstats), 
      R = ld_sumstats
    )
    
    # Save the estimated chi-square statistic
    saveRDS(chisq_val, "chisq_sumstat_result.rds")
    write.table(chisq_val, "chisq_sumstat_result.txt", row.names = FALSE, col.names = FALSE)
    
    # -----------------------------------------------------------------------------
    # --- Run Multi-INTACT (Standard Workflow) ---
    # -----------------------------------------------------------------------------
    message("Running Multi-INTACT (standard)...")
    
    rst <- INTACT::multi_intact(df = multi_simdat)
    
    # Save standard results
    saveRDS(rst, "multi_intact_results.rds")
    if (is.list(rst) && length(rst) >= 1 && is.data.frame(rst[[1]])) {
      write.csv(rst[[1]], "multi_intact_results_table.csv", row.names = FALSE)
    }
    
    # -----------------------------------------------------------------------------
    # --- Run Multi-INTACT with Model Posteriors ---
    # -----------------------------------------------------------------------------
    message("Running Multi-INTACT with model posteriors...")
    
    rst_post <- INTACT::multi_intact(df = multi_simdat, return_model_posteriors = TRUE)
    
    # Save model posteriors results
    saveRDS(rst_post, "multi_intact_posteriors.rds")
    if (is.list(rst_post) && length(rst_post) >= 1 && is.data.frame(rst_post[[1]])) {
      write.csv(rst_post[[1]], "multi_intact_posteriors_table.csv", row.names = FALSE)
    }
    
    # -----------------------------------------------------------------------------
    # --- Run Multi-INTACT without EM Algorithm ---
    # -----------------------------------------------------------------------------
    message("Running Multi-INTACT without EM algorithm...")
    
    rst_no_em <- INTACT::multi_intact(df = multi_simdat, em_algorithm = FALSE)
    
    # Save no-EM results
    saveRDS(rst_no_em, "multi_intact_no_em.rds")
    if (is.data.frame(rst_no_em)) {
      write.csv(rst_no_em, "multi_intact_no_em_table.csv", row.names = FALSE)
    }
    
    # -----------------------------------------------------------------------------
    # --- Visualization of Results ---
    # -----------------------------------------------------------------------------
    message("Generating diagnostic plots...")
    
    tryCatch({
      pdf("multi_intact_plots.pdf", width = 8, height = 10)
      
      # Extract the main output data frame from the standard run
      output <- rst[[1]]
      
      # Plot 1: Histogram of GPPC
      p1 <- ggplot(output, aes(x = GPPC)) +
        geom_histogram(binwidth = 0.01, fill = "grey40", color = "black") +
        ylab("Number of simulated genes") +
        theme_bw() +
        theme(text = element_text(size = 10, face = "bold")) +
        ggtitle("Distribution of Gene Probabilities of Putative Causality (GPPC)")
      
      print(p1)
      
      # Plot 2: Faceted histogram of GPRPs
      gprp1 <- data.frame("GPRP" = output\$GPRP_1, "Gene_product" = "Expression")
      gprp2 <- data.frame("GPRP" = output\$GPRP_2, "Gene_product" = "Protein")
      gprp <- rbind.data.frame(gprp1, gprp2)
      
      p2 <- ggplot(gprp, aes(x = GPRP, fill = Gene_product)) +
        geom_histogram(binwidth = 0.01, color = "black") +
        facet_wrap(~Gene_product) +
        ylab("Number of simulated genes") + 
        scale_fill_manual(values = c("blue", "red")) +
        theme_bw() +
        theme(text = element_text(size = 10, face = "bold"),
              legend.position = "none") +
        ggtitle("Distribution of Gene Product Relevance Probabilities (GPRP)")
      
      print(p2)
      
      dev.off()
      message("Plots successfully saved to 'multi_intact_plots.pdf'")
    }, error = function(e) {
      warning("An error occurred during plotting: ", e\$message)
    })
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_INTACT_MULTI_INTACT":',
        paste0('    INTACT: ', as.character(packageVersion('INTACT')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multi_intact.csv versions.yml
    """
}

workflow BIOC_INTACT_MULTI_INTACT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ z_sumstats, exprwt_sumstats, protwt_sumstats, ld_sumstats, multi_simdat ] ]

    main:
    BIOC_INTACT_MULTI_INTACT(ch_input)

    emit:
    tables   = BIOC_INTACT_MULTI_INTACT.out.tables
    plots    = BIOC_INTACT_MULTI_INTACT.out.plots
    objects  = BIOC_INTACT_MULTI_INTACT.out.objects
    versions = BIOC_INTACT_MULTI_INTACT.out.versions
}
