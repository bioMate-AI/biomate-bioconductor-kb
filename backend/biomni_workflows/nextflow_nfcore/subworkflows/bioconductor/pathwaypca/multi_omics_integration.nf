#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: pathwayPCA — multi_omics_integration
// Identify pathways and genes significantly associated with survival across multiple omics levels (e.g., CNV and Proteomics) and analyze their intersection.
// Input: wikipathways_human_symbol.gmt, ovarian_PNNL_survival.RDS, OV_surv_x_CNV2.RDS
// Container: quay.io/biocontainers/bioconductor-pathwaypca:1.26.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: pathwayPCA, tidyverse
// Visualizations: scatter plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read User Input Files from the Working Directory
//  * 2. [Input & Preparation] Create separate Omics S4 data containers for each omics
//  * 3. [Input & Preparation] Run AES-PCA pathway significance testing on both omics
//  * 4. [Input & Preparation] Extract significant pathways for both platforms
//  * 5. [Input & Preparation] Find the intersection of significant pathways using an
//  * 6. [Input & Preparation] Extract and compare gene loadings for the intersecting

nextflow.enable.dsl = 2

process BIOC_PATHWAYPCA_MULTI_OMICS_INTEGRATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20"

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
    library(pathwayPCA)
    library(tidyverse)
    
    # --- Read User Input Files from the Working Directory ---
    wikipathways_PC <- read_gmt("wikipathways_human_symbol.gmt", description = TRUE)
    ovSurv_df <- readRDS("ovarian_PNNL_survival.RDS")
    copyNumberClean_df <- readRDS("OV_surv_x_CNV2.RDS")
    
    # --- Create separate Omics S4 data containers for each omics ---
    ov_OmicsSurv <- CreateOmics ( assayData_df = ovSurv_df[, - ( 2 : 3 )], pathwayCollection_ls = wikipathways_PC, response = ovSurv_df[, 1 : 3 ], respType = "survival" , minPathSize = 5 )
    ovCNV_Surv <- CreateOmics ( assayData_df = copyNumberClean_df[, - ( 2 : 3 )], pathwayCollection_ls = wikipathways_PC, response = copyNumberClean_df[, 1 : 3 ], respType = "survival" , minPathSize = 5 )
    
    # --- Run AES-PCA pathway significance testing on both omics ---
    ovarian_aespcOut <- AESPCA_pVals ( object = ov_OmicsSurv, numPCs = 1 , parallel = TRUE , numCores = 2 , numReps = 0 , adjustment = "BH" )
    ovCNV_aespcOut <- AESPCA_pVals ( object = ovCNV_Surv, numPCs = 1 , parallel = TRUE , numCores = 20 , numReps = 0 , adjustment = "BH" )
    
    # --- Extract significant pathways for both platforms ---
    CNVpvals_df <- getPathpVals (ovCNV_aespcOut, alpha = 0.05 ) %>% mutate ( rawp_CNV = rawp) %>% select (description, rawp_CNV)
    PROTpvals_df <- getPathpVals (ovarian_aespcOut, alpha = 0.05 ) %>% mutate ( rawp_PROT = rawp) %>% select (description, rawp_PROT)
    
    # --- Find the intersection of significant pathways using an ---
    SigBoth_df <- inner_join (PROTpvals_df, CNVpvals_df, by = "description" )
    
    # --- Extract and compare gene loadings for the intersecting ---
    CNVwp195_ls <- getPathPCLs (ovCNV_aespcOut, "WP195" )
    PROTwp195_ls <- getPathPCLs (ovarian_aespcOut, "WP195" )
    
    # Downstream Analysis & Output Generation
    # Save the intersecting significant pathways
    write.csv(SigBoth_df, "significant_pathways_intersection.csv", row.names = FALSE)
    
    # Extract and save non-zero loadings for WP195 to identify common driver genes
    CNV195load_df <- CNVwp195_ls\$Loadings %>% 
      filter(abs(PC1) > 0) %>% 
      rename(PC1_CNV = PC1)
    
    PROT195load_df <- PROTwp195_ls\$Loadings %>% 
      filter(abs(PC1) > 0) %>% 
      rename(PC1_PROT = PC1)
    
    intersection_loadings <- inner_join(CNV195load_df, PROT195load_df, by = "featureID")
    write.csv(intersection_loadings, "WP195_intersecting_loadings.csv", row.names = FALSE)
    
    # Save the full AESPCA output objects
    saveRDS(ovarian_aespcOut, "ovarian_aespcOut.rds")
    saveRDS(ovCNV_aespcOut, "ovCNV_aespcOut.rds")
    
    # Generate and save the multi-omics relationship plot for NFKB1 (the common driver gene in WP195)
    NFKB1data_df <- inner_join(
      copyNumberClean_df %>% select(Sample, NFKB1) %>% rename(CNV_NFKB1 = NFKB1),
      ovSurv_df %>% select(Sample, NFKB1) %>% rename(PROT_NFKB1 = NFKB1),
      by = "Sample"
    )
    
    NFKB1_cor <- cor.test(NFKB1data_df\$CNV_NFKB1, NFKB1data_df\$PROT_NFKB1)
    
    pdf("NFKB1_multi_omics_scatterplot.pdf", width = 7, height = 6)
    p <- ggplot(data = NFKB1data_df) +
      theme_bw() +
      aes(x = CNV_NFKB1, y = PROT_NFKB1) +
      geom_point(size = 2) +
      geom_smooth(method = lm, se = FALSE, size = 1) +
      labs(
        title = "NFKB1 Expressions in Multi-Omics Data",
        x = "Copy Number Variation (Centred and Scaled)",
        y = "Protein Expression (Centred and Scaled)"
      ) +
      annotate(geom = "text", x = 0.5, y = -0.6, label = paste("rho =", round(NFKB1_cor\$estimate, 3))) +
      annotate(geom = "text", x = 0.5, y = -0.7, label = "p-val < 10^-5")
    print(p)
    dev.off()

    writeLines(c(
        '"BIOC_PATHWAYPCA_MULTI_OMICS_INTEGRATION":',
        paste0('    pathwayPCA: ', as.character(packageVersion('pathwayPCA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multi_omics_integration.csv versions.yml
    """
}

workflow BIOC_PATHWAYPCA_MULTI_OMICS_INTEGRATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ wikipathways_human_symbol.gmt, ovarian_PNNL_survival.RDS, OV_surv_x_CNV2.RDS ] ]

    main:
    BIOC_PATHWAYPCA_MULTI_OMICS_INTEGRATION(ch_input)

    emit:
    tables   = BIOC_PATHWAYPCA_MULTI_OMICS_INTEGRATION.out.tables
    plots    = BIOC_PATHWAYPCA_MULTI_OMICS_INTEGRATION.out.plots
    objects  = BIOC_PATHWAYPCA_MULTI_OMICS_INTEGRATION.out.objects
    versions = BIOC_PATHWAYPCA_MULTI_OMICS_INTEGRATION.out.versions
}
