#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: pathwayPCA — standard_pathway_association
// Test pathway association with phenotypes (e.g., survival) using AES-PCA or SuperPCA and extract significant pathways and gene loadings.
// Input: wikipathways_human_symbol.gmt, ovarian_PNNL_survival.RDS
// Container: quay.io/biocontainers/bioconductor-pathwaypca:1.26.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: pathwayPCA, survival, tidyverse
// Visualizations: bar plot, heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Import the pathway collection from a GMT file
//  * 2. [Input & Preparation] Create an Omics S4 data container using CreateOmics
//  * 3. [Input & Preparation] Perform pathway significance testing using AESPCA_pVals
//  * 4. [Input & Preparation] Extract and sort pathway p-values using getPathpVals
//  * 5. [Input & Preparation] Extract pathway-specific principal components and gene
//  * 6. [Input & Preparation] Subset the original assay data for a specific pathway

nextflow.enable.dsl = 2

process BIOC_PATHWAYPCA_STANDARD_PATHWAY_ASSOCIATION {
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
    .bm_deps <- c("pathwayPCA", "tidyverse", "survival")
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
    library(pathwayPCA)
    library(tidyverse)
    library(survival)
    
    # --- Import the pathway collection from a GMT file ---
    # Reading the user-provided GMT file from the working directory
    wikipathways_PC <- read_gmt("wikipathways_human_symbol.gmt", description = TRUE)
    
    # Load the user-provided assay and survival phenotype data frame
    ovSurv_df <- readRDS("ovarian_PNNL_survival.RDS")
    
    # --- Create an Omics S4 data container using CreateOmics ---
    # Specifying the assay data, pathway collection, response, and response type
    ov_OmicsSurv <- CreateOmics(
      assayData_df = ovSurv_df[, - ( 2 : 3 )],
      pathwayCollection_ls = wikipathways_PC,
      response = ovSurv_df[, 1 : 3 ],
      respType = "survival",
      minPathSize = 5
    )
    
    # --- Perform pathway significance testing using AESPCA_pVals ---
    ovarian_aespcOut <- AESPCA_pVals(
      object = ov_OmicsSurv,
      numPCs = 1,
      parallel = TRUE,
      numCores = 2,
      numReps = 0,
      adjustment = "BH"
    )
    
    # --- Extract and sort pathway p-values using getPathpVals ---
    top10_pvals <- getPathpVals(ovarian_aespcOut, numPaths = 10)
    write.csv(top10_pvals, "top10_pathways_pvals.csv", row.names = FALSE)
    
    # --- Extract pathway-specific principal components and gene ---
    wp195PCLs_ls <- getPathPCLs(ovarian_aespcOut, "WP195")
    saveRDS(wp195PCLs_ls, "wp195_PCLs.rds")
    
    # Extract and save non-zero loadings for WP195
    wp195Loadings_df <- wp195PCLs_ls\$Loadings %>% filter(PC1 != 0)
    write.csv(wp195Loadings_df, "wp195_loadings.csv", row.names = FALSE)
    
    # --- Subset the original assay data for a specific pathway ---
    wp195Data_df <- SubsetPathwayData(ov_OmicsSurv, "WP195")
    write.csv(wp195Data_df, "wp195_assay_subset.csv", row.names = FALSE)
    
    # --- Visualizations and Additional Outputs ---
    
    # Plot 1: Pathway significance level for the top 20 pathways
    ovOutGather_df <- getPathpVals(ovarian_aespcOut, score = TRUE)
    p1 <- ggplot(ovOutGather_df) +
      theme_bw() +
      aes(x = reorder(terms, score), y = score) +
      geom_col(position = "dodge", fill = "#66FFFF", width = 0.7) +
      geom_text(aes(x = reorder(terms, score), label = reorder(description, score), y = 0.1), color = "black", size = 2, hjust = 0) +
      ggtitle("AES-PCA Significant Pathways: Ovarian Cancer") +
      xlab("Pathways") +
      ylab("Negative LN (p-Value)") +
      geom_hline(yintercept = -log(0.01), linewidth = 1, color = "blue") +
      coord_flip()
    ggsave("top_pathways_bar_plot.pdf", plot = p1, width = 10, height = 8)
    
    # Plot 2: Gene Loadings on IL-1 Signaling Pathway (WP195)
    wp195Loadings_df_plot <- wp195Loadings_df %>%
      arrange(desc(abs(PC1))) %>%
      mutate(featureID = factor(featureID, levels = featureID)) %>%
      mutate(Direction = factor(ifelse(PC1 > 0, "Up", "Down")))
    
    p2 <- ggplot(data = wp195Loadings_df_plot) +
      theme_bw() +
      aes(x = featureID, y = PC1, fill = Direction) +
      geom_col(width = 0.5, fill = "#005030", color = "#f47321") +
      labs(title = "Gene Loadings on IL-1 Signaling Pathway", x = "Protein", y = "Loadings of PC1") +
      theme(legend.position = "none")
    ggsave("wp195_gene_loadings.pdf", plot = p2, width = 8, height = 6)
    
    # Plot 3: Distribution of Sample-specific Estimate of Pathway Activities
    p3 <- ggplot(data = wp195PCLs_ls\$PCs) +
      theme_classic() +
      aes(x = V1) +
      geom_histogram(bins = 10, color = "#005030", fill = "#f47321") +
      labs(title = "Distribution of Sample-specific Estimate of Pathway Activities",
           subtitle = paste0(wp195PCLs_ls\$pathway, ": ", wp195PCLs_ls\$description),
           x = "PC1 Value for Each Sample", y = "Count")
    ggsave("wp195_sample_activities_histogram.pdf", plot = p3, width = 8, height = 6)
    
    # Plot 4: Heatmap of the proteins in WP195 pathway
    wp195gather_df <- wp195Data_df %>%
      arrange(EventTime) %>%
      select(-EventTime, -EventObs) %>%
      gather(protein, value, -sampleID)
    
    p4 <- ggplot(wp195gather_df, aes(x = protein, y = sampleID)) +
      geom_tile(aes(fill = value)) +
      scale_fill_gradient2(low = "red", mid = "black", high = "green") +
      labs(x = "Proteins", y = "Subjects", fill = "Protein level") +
      theme(axis.text.x = element_text(angle = 90)) +
      coord_flip()
    ggsave("wp195_heatmap.pdf", plot = p4, width = 10, height = 12)

    writeLines(c(
        '"BIOC_PATHWAYPCA_STANDARD_PATHWAY_ASSOCIATION":',
        paste0('    pathwayPCA: ', as.character(packageVersion('pathwayPCA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_pathway_association.csv versions.yml
    """
}

workflow BIOC_PATHWAYPCA_STANDARD_PATHWAY_ASSOCIATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ wikipathways_human_symbol.gmt, ovarian_PNNL_survival.RDS ] ]

    main:
    BIOC_PATHWAYPCA_STANDARD_PATHWAY_ASSOCIATION(ch_input)

    emit:
    tables   = BIOC_PATHWAYPCA_STANDARD_PATHWAY_ASSOCIATION.out.tables
    plots    = BIOC_PATHWAYPCA_STANDARD_PATHWAY_ASSOCIATION.out.plots
    objects  = BIOC_PATHWAYPCA_STANDARD_PATHWAY_ASSOCIATION.out.objects
    versions = BIOC_PATHWAYPCA_STANDARD_PATHWAY_ASSOCIATION.out.versions
}
