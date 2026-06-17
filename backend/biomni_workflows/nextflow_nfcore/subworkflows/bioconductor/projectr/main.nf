#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: projectR — pca_nmf_projection
// Project a target expression matrix into a latent space defined by PCA eigenvectors or NMF/CoGAPS amplitude loadings.
// Input: target_expression.csv, training_expression.csv
// Container: quay.io/biocontainers/bioconductor-projectr:1.26.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: projectR
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Perform PCA on the training dataset using prcomp or load pre-computed CoGAPS amplitude loadings
//  * 2. [Core Analysis] Project the target dataset into the defined loadings space using projectR

nextflow.enable.dsl = 2

process BIOC_PROJECTR_PCA_NMF_PROJECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("projectR")
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
        library(projectR)
        
        # ----------------------------------------------------------------------
        # 1. Read User Input Files
        # ----------------------------------------------------------------------
        # Read training expression matrix (genes as rows, samples as columns)
        train_data <- read.csv("training_expression.csv", check.names = FALSE)
        if (is.character(train_data[[1]]) || is.factor(train_data[[1]])) {
          rownames(train_data) <- train_data[[1]]
          train_data <- train_data[, -1, drop = FALSE]
        }
        p.RNAseq6l3c3t <- as.matrix(train_data)
        
        # Read target expression matrix (genes as rows, samples as columns)
        target_data <- read.csv("target_expression.csv", check.names = FALSE)
        if (is.character(target_data[[1]]) || is.factor(target_data[[1]])) {
          rownames(target_data) <- target_data[[1]]
          target_data <- target_data[, -1, drop = FALSE]
        }
        p.ESepiGen4c1l <- list(mRNA.Seq = as.matrix(target_data))
        
        # Define the gene symbols mapping vector for the target dataset
        map.ESepiGen4c1l <- list(GeneSymbols = rownames(p.ESepiGen4c1l\$mRNA.Seq))
        
        # ----------------------------------------------------------------------
        # 2. Perform PCA on Training Dataset & Define Loadings
        # ----------------------------------------------------------------------
        # Perform PCA on the training dataset
        pc.RNAseq6l3c3t <- prcomp(t(p.RNAseq6l3c3t))
        
        # ----------------------------------------------------------------------
        # 3. Project Target Dataset into Latent Spaces (Documented Code)
        # ----------------------------------------------------------------------
        # Project target dataset into PCA space
        PCA2ESepi <- projectR(data = p.ESepiGen4c1l\$mRNA.Seq, loadings = pc.RNAseq6l3c3t, full = TRUE, dataNames = map.ESepiGen4c1l[["GeneSymbols"]])
        
        # ----------------------------------------------------------------------
        # 4. Save Outputs
        # ----------------------------------------------------------------------
        # Save full projection fit objects as RDS
        saveRDS(PCA2ESepi, "pca_projection_full.rds")
        
        # Save projected patterns (sample coordinates in latent space) as CSV
        write.csv(as.data.frame(PCA2ESepi[[1]]), "pca_projection_patterns.csv", row.names = TRUE)
        
        # Generate and save visualization plots
        pdf("projection_plots.pdf", width = 5, height = 5)
        par(mfrow = c(1, 1))
        
        # Plot PCA projection (first two components)
        plot(t(PCA2ESepi[[1]])[, 1:2], col = "blue", pch = 19,
             main = "PCA Projection", xlab = "Projected PC1", ylab = "Projected PC2")
        text(t(PCA2ESepi[[1]])[, 1:2], labels = colnames(p.ESepiGen4c1l\$mRNA.Seq), pos = 3, cex = 0.7)
        
        dev.off()
        
        cat("Pipeline completed successfully. Outputs saved to working directory.\n")

    writeLines(c(
        '"BIOC_PROJECTR_PCA_NMF_PROJECTION":',
        paste0('    projectR: ', as.character(packageVersion('projectR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pca_nmf_projection.csv versions.yml
    """
}

workflow BIOC_PROJECTR_PCA_NMF_PROJECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ target_expression.csv, training_expression.csv ] ]

    main:
    BIOC_PROJECTR_PCA_NMF_PROJECTION(ch_input)

    emit:
    tables   = BIOC_PROJECTR_PCA_NMF_PROJECTION.out.tables
    plots    = BIOC_PROJECTR_PCA_NMF_PROJECTION.out.plots
    objects  = BIOC_PROJECTR_PCA_NMF_PROJECTION.out.objects
    versions = BIOC_PROJECTR_PCA_NMF_PROJECTION.out.versions
}
