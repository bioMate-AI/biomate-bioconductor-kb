#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Linnorm — cell_subpopulation_clustering
// Perform cell subpopulation clustering using t-SNE, PCA, or Hierarchical Clustering.
// Input: Islam2011
// Container: quay.io/biocontainers/bioconductor-linnorm:2.34.0--r45ha27e39d_0
// R packages: Linnorm
// Bioconductor: 3.20 | R: 4.4
// Requires: Linnorm
// Visualizations: cluster plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run t-SNE k-means clustering with or without known group annotations
//  * 2. [Core Analysis] Run PCA k-means clustering with or without known group annotations
//  * 3. [Visualization & Output] Run Hierarchical Clustering and plot the dendrogram

nextflow.enable.dsl = 2

process BIOC_LINNORM_CELL_SUBPOPULATION_CLUSTERING {
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
    .bm_deps <- c("Linnorm")
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
        library(Linnorm)
        
        # -----------------------------------------------------------------------------
        # 1. Read User Input File
        # -----------------------------------------------------------------------------
        # The pipeline expects 'Islam2011' in the working directory.
        # We will attempt to read it as RDS, or fallback to common text formats.
        if (file.exists("Islam2011")) {
          Islam2011 <- tryCatch(readRDS("Islam2011"), error = function(e) {
            tryCatch(as.matrix(read.table("Islam2011", header = TRUE, row.names = 1, sep = "\t")), error = function(e2) {
              as.matrix(read.csv("Islam2011", header = TRUE, row.names = 1))
            })
          })
        } else if (file.exists("Islam2011.rds")) {
          Islam2011 <- readRDS("Islam2011.rds")
        } else if (file.exists("Islam2011.csv")) {
          Islam2011 <- as.matrix(read.csv("Islam2011.csv", header = TRUE, row.names = 1))
        } else if (file.exists("Islam2011.txt")) {
          Islam2011 <- as.matrix(read.table("Islam2011.txt", header = TRUE, row.names = 1, sep = "\t"))
        } else if (file.exists("Islam2011.tsv")) {
          Islam2011 <- as.matrix(read.table("Islam2011.tsv", header = TRUE, row.names = 1, sep = "\t"))
        } else {
          stop("Required input file 'Islam2011' (matrix of expression values) not found in the working directory.")
        }
        
        # Ensure it is a matrix
        Islam2011 <- as.matrix(Islam2011)
        
        # -----------------------------------------------------------------------------
        # 2. Setup Output PDF for Plots
        # -----------------------------------------------------------------------------
        pdf("cell_subpopulation_clustering_plots.pdf", width = 8, height = 8)
        
        # -----------------------------------------------------------------------------
        # 3. t-SNE K-means Clustering
        # -----------------------------------------------------------------------------
        message("Running t-SNE clustering without group annotations...")
        tSNE.results1 <- Linnorm.tSNE(Islam2011)
        print(tSNE.results1\$plot\$plot)
        
        # Define groups dynamically based on the number of columns
        half_cols <- floor(ncol(Islam2011) / 2)
        Groups <- c(rep("Group1", half_cols), rep("Group2", ncol(Islam2011) - half_cols))
        
        message("Running t-SNE clustering with known group annotations...")
        tSNE.results2 <- Linnorm.tSNE(Islam2011, Group = Groups, num_center = 2)
        print(tSNE.results2\$plot\$plot)
        
        # Save t-SNE results
        saveRDS(tSNE.results1, "tSNE_results_no_groups.rds")
        saveRDS(tSNE.results2, "tSNE_results_with_groups.rds")
        
        # -----------------------------------------------------------------------------
        # 4. PCA K-means Clustering
        # -----------------------------------------------------------------------------
        message("Running PCA clustering without group annotations...")
        PCA.results1 <- Linnorm.PCA(Islam2011)
        print(PCA.results1\$plot\$plot)
        
        message("Running PCA clustering with known group annotations...")
        PCA.results2 <- Linnorm.PCA(Islam2011, Group = Groups, num_center = 2, num_PC = 3)
        print(PCA.results2\$plot\$plot)
        
        # Save PCA results
        saveRDS(PCA.results1, "PCA_results_no_groups.rds")
        saveRDS(PCA.results2, "PCA_results_with_groups.rds")
        
        # -----------------------------------------------------------------------------
        # 5. Hierarchical Clustering
        # -----------------------------------------------------------------------------
        message("Running Hierarchical Clustering...")
        Islam <- Islam2011
        
        # Use the dynamically generated generic groups
        Group <- Groups
        colnames(Islam) <- paste(colnames(Islam), Group, sep = "_")
        
        # Note that there are 2 known clusters.
        HClust.Results <- Linnorm.HClust(Islam, Group = Group,
          num_Clust = 2, fontsize = 1.5, Color = c("Red", "Blue"), RectColor = "Green")
        
        print(HClust.Results\$plot\$plot)
        
        # Save Hierarchical Clustering results
        saveRDS(HClust.Results, "HClust_results.rds")
        
        # Close PDF device
        dev.off()
        
        message("Pipeline completed successfully. Outputs saved to 'cell_subpopulation_clustering_plots.pdf' and RDS files.")

    writeLines(c(
        '"BIOC_LINNORM_CELL_SUBPOPULATION_CLUSTERING":',
        paste0('    Linnorm: ', as.character(packageVersion('Linnorm')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cell_subpopulation_clustering.csv versions.yml
    """
}

workflow BIOC_LINNORM_CELL_SUBPOPULATION_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Islam2011 ] ]

    main:
    BIOC_LINNORM_CELL_SUBPOPULATION_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_LINNORM_CELL_SUBPOPULATION_CLUSTERING.out.tables
    plots    = BIOC_LINNORM_CELL_SUBPOPULATION_CLUSTERING.out.plots
    objects  = BIOC_LINNORM_CELL_SUBPOPULATION_CLUSTERING.out.objects
    versions = BIOC_LINNORM_CELL_SUBPOPULATION_CLUSTERING.out.versions
}
