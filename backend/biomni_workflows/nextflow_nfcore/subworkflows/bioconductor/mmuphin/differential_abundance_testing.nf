#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MMUPHin — differential_abundance_testing
// Perform meta-analytic differential abundance and prevalence testing across multiple cohorts to identify consistent microbial associations.
// Input: adjusted_abundance_table.tsv, metadata.tsv
// Container: quay.io/biocontainers/bioconductor-mmuphin:1.16.0--r43hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MMUPHin, dplyr, ggplot2, magrittr
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run maaslin_meta to perform regression within individual batches and aggregate results
//  * 2. [Core Analysis] Extract meta-analysis results for abundance and prevalence testing

nextflow.enable.dsl = 2

process BIOC_MMUPHIN_DIFFERENTIAL_ABUNDANCE_TESTING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metagenomics:3.20"

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
        
        # Load required libraries
        library(MMUPHin)
        library(magrittr)
        library(dplyr)
        library(ggplot2)
        
        # 1. Read user input files from the working directory
        # The abundance table is expected to be a feature-by-sample matrix
        CRC_abd_adj <- as.matrix(read.table("adjusted_abundance_table.tsv", 
                                            sep = "\t", 
                                            header = TRUE, 
                                            row.names = 1, 
                                            check.names = FALSE))
        
        # The metadata table is expected to have sample IDs as row names matching the abundance table columns
        CRC_meta <- read.table("metadata.tsv", 
                               sep = "\t", 
                               header = TRUE, 
                               row.names = 1, 
                               check.names = FALSE)
        
        # Ensure sample IDs match exactly between abundance matrix columns and metadata rows
        common_samples <- intersect(colnames(CRC_abd_adj), rownames(CRC_meta))
        if (length(common_samples) == 0) {
          stop("Error: No matching sample IDs found between adjusted_abundance_table.tsv and metadata.tsv")
        }
        CRC_abd_adj <- CRC_abd_adj[, common_samples, drop = FALSE]
        CRC_meta <- CRC_meta[common_samples, , drop = FALSE]
        
        # 2. Run maaslin_meta to perform regression within individual batches and aggregate results
        # Dynamically assign batch, exposure, and covariates based on metadata columns
        # Assuming 1st column is batch, 2nd is exposure, and the rest are covariates
        batch_var <- colnames(CRC_meta)[1]
        exposure_var <- colnames(CRC_meta)[2]
        covariate_vars <- if (ncol(CRC_meta) > 2) colnames(CRC_meta)[3:ncol(CRC_meta)] else NULL
        
        fit_maaslin_meta <- maaslin_meta(feature_abd = CRC_abd_adj,
                               batch = batch_var,
                               exposure = exposure_var,
                               covariates = covariate_vars,
                               data = CRC_meta,
                               control = list(verbose = FALSE))
        
        # 3. Extract meta-analysis results for abundance and prevalence testing
        meta_fits_abundance <- fit_maaslin_meta\$meta_fits_abundance
        meta_fits_prevalence <- fit_maaslin_meta\$meta_fits_prevalence
        
        # 4. Write meaningful results to output files
        # Save tabular results
        write.csv(meta_fits_abundance, "meta_fits_abundance.csv", row.names = FALSE)
        write.csv(meta_fits_prevalence, "meta_fits_prevalence.csv", row.names = FALSE)
        
        # Save the complete model object
        saveRDS(fit_maaslin_meta, "fit_maaslin_meta.rds")
        
        # Generate and save diagnostic plots for significant associations (FDR q < 0.05)
        pdf("differential_abundance_plots.pdf", width = 10, height = 8)
        
        # Abundance plot
        tryCatch({
          sig_abundance <- meta_fits_abundance %>% 
            filter(qval.fdr < 0.05) %>% 
            arrange(coef) %>% 
            mutate(feature = factor(feature, levels = feature))
          
          if (nrow(sig_abundance) > 0) {
            p1 <- ggplot(sig_abundance, aes(y = coef, x = feature)) +
              geom_bar(stat = "identity") +
              coord_flip() +
              theme_minimal() +
              ggtitle("Significant Differentially Abundant Features (FDR < 0.05)")
            print(p1)
          } else {
            grid::grid.newpage()
            grid::grid.text("No features with significant differential abundance (FDR < 0.05)")
          }
        }, error = function(e) {
          warning("Could not generate abundance plot: ", e\$message)
        })
        
        # Prevalence plot
        tryCatch({
          sig_prevalence <- meta_fits_prevalence %>% 
            filter(qval.fdr < 0.05) %>% 
            arrange(coef) %>% 
            mutate(feature = factor(feature, levels = feature))
          
          if (nrow(sig_prevalence) > 0) {
            p2 <- ggplot(sig_prevalence, aes(y = coef, x = feature)) +
              geom_bar(stat = "identity") +
              coord_flip() +
              theme_minimal() +
              ggtitle("Significant Differentially Prevalent Features (FDR < 0.05)")
            print(p2)
          } else {
            grid::grid.newpage()
            grid::grid.text("No features with significant differential prevalence (FDR < 0.05)")
          }
        }, error = function(e) {
          warning("Could not generate prevalence plot: ", e\$message)
        })
        
        dev.off()

    writeLines(c(
        '"BIOC_MMUPHIN_DIFFERENTIAL_ABUNDANCE_TESTING":',
        paste0('    MMUPHin: ', as.character(packageVersion('MMUPHin')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_abundance_testing.csv versions.yml
    """
}

workflow BIOC_MMUPHIN_DIFFERENTIAL_ABUNDANCE_TESTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ adjusted_abundance_table.tsv, metadata.tsv ] ]

    main:
    BIOC_MMUPHIN_DIFFERENTIAL_ABUNDANCE_TESTING(ch_input)

    emit:
    tables   = BIOC_MMUPHIN_DIFFERENTIAL_ABUNDANCE_TESTING.out.tables
    plots    = BIOC_MMUPHIN_DIFFERENTIAL_ABUNDANCE_TESTING.out.plots
    objects  = BIOC_MMUPHIN_DIFFERENTIAL_ABUNDANCE_TESTING.out.objects
    versions = BIOC_MMUPHIN_DIFFERENTIAL_ABUNDANCE_TESTING.out.versions
}
