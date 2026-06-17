#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: betaHMM — dmc_dmr_detection
// Identify differentially methylated CpG sites (DMCs) and regions (DMRs) from untransformed beta values and annotation data.
// Input: pca_methylation_data, annotation_data
// Container: quay.io/biocontainers/bioconductor-betahmm:1.6.0--r45hdfd78af_0
// R packages: SummarizedExperiment, betaHMM
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, betaHMM
// Visualizations: density plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Estimate model parameters and hidden states using betaHMM
//  * 2. [Core Analysis] Identify DMCs using dmc_identification
//  * 3. [Core Analysis] Identify DMRs from identified DMCs using dmr_identification
//  * 4. [Visualization & Output] Plot fitted densities, uncertainties, and identified regions using plot

nextflow.enable.dsl = 2

process BIOC_BETAHMM_DMC_DMR_DETECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("SummarizedExperiment", "betaHMM")
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
        library(betaHMM)
        
        library(SummarizedExperiment)
        # Helper function to load user input files with various extensions
        load_input_file <- function(base_name) {
          extensions <- c(".csv", ".tsv", ".rds", ".txt", "")
          for (ext in extensions) {
            file_path <- paste0(base_name, ext)
            if (file.exists(file_path)) {
              if (ext == ".rds") {
                return(readRDS(file_path))
              } else if (ext == ".tsv") {
                return(read.delim(file_path, header = TRUE, check.names = FALSE))
              } else if (ext == ".csv") {
                return(read.csv(file_path, header = TRUE, check.names = FALSE))
              } else {
                return(read.table(file_path, header = TRUE, check.names = FALSE))
              }
            }
          }
          stop(paste("Error: Required input file", base_name, "not found in the working directory."))
        }
        
        # Load user input data
        pca_methylation_data <- load_input_file("pca_methylation_data")
        annotation_data <- load_input_file("annotation_data")
        
        # Define parameters dynamically
        M <- 3 ## No. of methylation states in a DNA sample type
        
        # Dynamically determine N, R, and treatment_group from pca_methylation_data
        sample_names <- setdiff(colnames(pca_methylation_data), "IlmnID")
        groups <- gsub("[_\\\\.]?[0-9]+\$", "", sample_names)
        treatment_group <- unique(groups)
        R <- length(treatment_group)
        N <- as.integer(length(sample_names) / R)
        
        my.seed <- 321 ## set seed for reproducibility
        
        # 1. Estimate model parameters and hidden states using betaHMM
        betaHMM_out <- betaHMM(pca_methylation_data,
                                        annotation_data,
                                        M = M,
                                        N = N,
                                        R = R,
                                        parallel_process = FALSE,
                                        seed = my.seed,
                                        treatment_group = treatment_group)
        
        # Display estimated parameters
        A(betaHMM_out)
        phi(betaHMM_out)
        
        # Access hidden states for the first available chromosome (wrapped in tryCatch for robustness to custom data)
        first_chr_name <- names(hidden_states(betaHMM_out))[1]
        first_chr <- gsub("^chr\\\\s*", "", first_chr_name)
        
        tryCatch({
          print(head(hidden_states(betaHMM_out)[[first_chr_name]]))
        }, error = function(e) {
          warning(paste("Could not access hidden states for", first_chr_name, ":"), e\$message)
        })
        
        summary(betaHMM_out)
        
        # 2. Identify DMCs using dmc_identification
        dmc_out <- dmc_identification(betaHMM_out)
        dmc_df <- assay(dmc_out)
        head(dmc_df)
        summary(dmc_out)
        
        # Save DMC results
        write.csv(dmc_df, "dmc_results.csv", row.names = FALSE)
        saveRDS(dmc_out, "dmc_out.rds")
        saveRDS(betaHMM_out, "betaHMM_out.rds")
        
        # Calculate AUC metric
        AUC_chr <- AUC(dmc_out)
        
        # Plot fitted densities (wrapped in tryCatch for robustness to custom data)
        tryCatch({
          pdf("fitted_density_plot.pdf")
          plot(betaHMM_out, chromosome = first_chr, what = "fitted density", AUC = AUC_chr)
          dev.off()
        }, error = function(e) {
          warning("Fitted density plot failed: ", e\$message)
          if (dev.cur() > 1) dev.off()
        })
        
        # Plot uncertainty (wrapped in tryCatch for robustness to custom data)
        tryCatch({
          pdf("uncertainty_plot.pdf")
          plot(betaHMM_out, chromosome = first_chr, what = "uncertainty",
                  uncertainty_threshold = 0.2)
          dev.off()
        }, error = function(e) {
          warning("Uncertainty plot failed: ", e\$message)
          if (dev.cur() > 1) dev.off()
        })
        
        # 3. Identify DMRs from identified DMCs using dmr_identification
        dmr_out <- dmr_identification(dmc_out, parallel_process = FALSE)
        dmr_df <- assay(dmr_out)
        head(dmr_df)
        summary(dmr_out)
        
        # Save DMR results
        write.csv(dmr_df, "dmr_results.csv", row.names = FALSE)
        saveRDS(dmr_out, "dmr_out.rds")
        
        # 4. Plot identified regions (wrapped in tryCatch for robustness to custom data)
        tryCatch({
          first_cpg <- if (nrow(dmr_df) > 0) {
            as.character(dmr_df\$start_CpG[1])
          } else if (nrow(dmc_df) > 0) {
            as.character(dmc_df\$IlmnID[1])
          } else {
            as.character(pca_methylation_data\$IlmnID[1])
          }
          
          pdf("dmc_dmr_plot.pdf")
          plot(dmc_out, start_CpG = first_cpg, end_CpG = 15)
          dev.off()
        }, error = function(e) {
          warning("DMC/DMR plot failed: ", e\$message)
          if (dev.cur() > 1) dev.off()
        })

    writeLines(c(
        '"BIOC_BETAHMM_DMC_DMR_DETECTION":',
        paste0('    betaHMM: ', as.character(packageVersion('betaHMM')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dmc_dmr_detection.csv versions.yml
    """
}

workflow BIOC_BETAHMM_DMC_DMR_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pca_methylation_data, annotation_data ] ]

    main:
    BIOC_BETAHMM_DMC_DMR_DETECTION(ch_input)

    emit:
    tables   = BIOC_BETAHMM_DMC_DMR_DETECTION.out.tables
    plots    = BIOC_BETAHMM_DMC_DMR_DETECTION.out.plots
    objects  = BIOC_BETAHMM_DMC_DMR_DETECTION.out.objects
    versions = BIOC_BETAHMM_DMC_DMR_DETECTION.out.versions
}
