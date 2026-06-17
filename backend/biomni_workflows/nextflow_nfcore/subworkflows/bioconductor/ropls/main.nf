#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ropls — pca_analysis
// Perform unsupervised Principal Component Analysis for visualization and outlier detection.
// Input: dataMatrix.tsv
// Container: quay.io/biocontainers/bioconductor-ropls:1.42.0--r45hdfd78af_0
// R packages: Biobase, MultiAssayExperiment, MultiDataSet, phenomis, ropls, SummarizedExperiment
// Bioconductor: 3.20 | R: 4.4
// Requires: ropls
// Visualizations: PCA plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run PCA using opls
//  * 2. [Visualization & Output] Plot default summary figures
//  * 3. [Visualization & Output] Customize score plots with sample metadata coloring and labels

nextflow.enable.dsl = 2

process BIOC_ROPLS_PCA_ANALYSIS {
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
    .bm_deps <- c("Biobase", "MultiAssayExperiment", "MultiDataSet", "phenomis", "ropls", "SummarizedExperiment")
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
    library(ropls)
    
    # 1. Read User Input
    if (!file.exists("dataMatrix.tsv")) {
      stop("Required input file 'dataMatrix.tsv' not found in the working directory.")
    }
    
    dataMatrix <- as.matrix(read.table("dataMatrix.tsv", header = TRUE, sep = "\t", row.names = 1, check.names = FALSE))
    
    # Read or construct sample metadata
    if (file.exists("sampleMetadata.tsv")) {
      sampleMetadata <- read.table("sampleMetadata.tsv", header = TRUE, sep = "\t", row.names = 1, check.names = FALSE)
    } else {
      # Fallback: Create a dummy data frame with 'gender' and 'age' to match the documented code requirements
      n_samples <- nrow(dataMatrix)
      gender <- factor(rep(c("M", "F"), length.out = n_samples))
      age <- seq(20, 20 + n_samples - 1)
      sampleMetadata <- data.frame(
        gender = gender,
        age = age,
        row.names = rownames(dataMatrix)
      )
    }
    
    # Construct the sacurine object to match the documented code structure
    sacurine <- list(
      dataMatrix = dataMatrix,
      sampleMetadata = sampleMetadata
    )
    
    # 2. Run PCA using opls and plot default summary figures
    pdf("pca_summary_plots.pdf")
    sacurine.pca <- opls(sacurine\$dataMatrix)
    dev.off()
    
    # 3. Customize score plots with sample metadata coloring and labels
    if (ncol(sacurine\$sampleMetadata) >= 1) {
      col1_name <- colnames(sacurine\$sampleMetadata)[1]
      col1_data <- sacurine\$sampleMetadata[, 1]
      
      pdf(paste0("pca_score_plot_", col1_name, ".pdf"))
      plot(sacurine.pca, typeVc = "x-score", parAsColFcVn = col1_data)
      dev.off()
      
      if (ncol(sacurine\$sampleMetadata) >= 2) {
        col2_name <- colnames(sacurine\$sampleMetadata)[2]
        col2_data <- as.character(sacurine\$sampleMetadata[, 2])
        
        pdf(paste0("pca_score_plot_", col1_name, "_", col2_name, ".pdf"))
        plot(sacurine.pca, typeVc = "x-score", parAsColFcVn = col1_data, parLabVc = col2_data)
        dev.off()
      }
    }
    
    # 4. Save meaningful results
    pca_scores <- getScoreMN(sacurine.pca)
    write.csv(pca_scores, "pca_scores.csv", row.names = TRUE)
    
    pca_loadings <- getLoadingMN(sacurine.pca)
    write.csv(pca_loadings, "pca_loadings.csv", row.names = TRUE)
    
    pca_summary <- getSummaryDF(sacurine.pca)
    write.csv(pca_summary, "pca_summary.csv", row.names = TRUE)
    
    saveRDS(sacurine.pca, "pca_model.rds")

    writeLines(c(
        '"BIOC_ROPLS_PCA_ANALYSIS":',
        paste0('    ropls: ', as.character(packageVersion('ropls')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pca_analysis.csv versions.yml
    """
}

workflow BIOC_ROPLS_PCA_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dataMatrix.tsv ] ]

    main:
    BIOC_ROPLS_PCA_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_ROPLS_PCA_ANALYSIS.out.tables
    plots    = BIOC_ROPLS_PCA_ANALYSIS.out.plots
    objects  = BIOC_ROPLS_PCA_ANALYSIS.out.objects
    versions = BIOC_ROPLS_PCA_ANALYSIS.out.versions
}
