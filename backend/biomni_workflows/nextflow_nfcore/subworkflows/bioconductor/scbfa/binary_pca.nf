#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scBFA — binary_pca
// Perform dimensionality reduction on scRNA-seq gene detection patterns using Binary PCA.
// Input: exprdata
// Container: quay.io/biocontainers/bioconductor-scbfa:1.24.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, ggplot2, scBFA
// Visualizations: PCA plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Construct a SingleCellExperiment object from the raw count matrix
//  * 2. [Core Analysis] Run the BinaryPCA model to compute the principal components
//  * 3. [Visualization & Output] Extract the low-dimensional coordinates (x) for downstream visualization or analysis

nextflow.enable.dsl = 2

process BIOC_SCBFA_BINARY_PCA {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("scBFA", "ggplot2")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
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
    library(scBFA)
    library(ggplot2)
    
    # 1. Read the declared USER INPUT file from the working directory
    # Supporting CSV, TSV, or RDS formats for the raw counts matrix
    if (file.exists("exprdata.csv")) {
      exprdata <- as.matrix(read.csv("exprdata.csv", row.names = 1, check.names = FALSE))
    } else if (file.exists("exprdata.tsv")) {
      exprdata <- as.matrix(read.delim("exprdata.tsv", row.names = 1, check.names = FALSE))
    } else if (file.exists("exprdata.rds")) {
      exprdata <- readRDS("exprdata.rds")
      if (!is.matrix(exprdata)) {
        exprdata <- as.matrix(exprdata)
      }
    } else {
      stop("Error: Input file 'exprdata' (as .csv, .tsv, or .rds) not found in the working directory.")
    }
    
    # 2. Construct a SingleCellExperiment object from the raw count matrix
    sce <- SingleCellExperiment(assay = list(counts = exprdata))
    
    # 3. Run the BinaryPCA model to compute the principal components
    bpca = BinaryPCA(scData = sce) 
    
    # 4. Extract the low-dimensional coordinates (x) for downstream visualization or analysis
    df = as.data.frame(bpca\$x[,c(1:2)])
    
    # 5. Save meaningful results to output files
    # Save the coordinates to a CSV file
    write.csv(df, "binary_pca_coordinates.csv", row.names = TRUE)
    
    # Save the full BinaryPCA model object to an RDS file
    saveRDS(bpca, "binary_pca_model.rds")
    
    # Generate and save a visualization plot of the first two principal components
    colnames(df) <- c("V1", "V2")
    p1 <- ggplot(df, aes(x = V1, y = V2)) +
      geom_point(size = 2.5, alpha = 0.8, color = "#377EB8") +
      xlab("PC 1") +
      ylab("PC 2") +
      theme_bw() +
      theme(
        panel.grid.major = element_blank(),
        panel.grid.minor = element_blank(),
        axis.line = element_line(color = "black")
      )
    
    ggsave("binary_pca_plot.pdf", plot = p1, width = 8, height = 6)

    writeLines(c(
        '"BIOC_SCBFA_BINARY_PCA":',
        paste0('    scBFA: ', as.character(packageVersion('scBFA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_binary_pca.csv versions.yml
    """
}

workflow BIOC_SCBFA_BINARY_PCA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ exprdata ] ]

    main:
    BIOC_SCBFA_BINARY_PCA(ch_input)

    emit:
    tables   = BIOC_SCBFA_BINARY_PCA.out.tables
    plots    = BIOC_SCBFA_BINARY_PCA.out.plots
    objects  = BIOC_SCBFA_BINARY_PCA.out.objects
    versions = BIOC_SCBFA_BINARY_PCA.out.versions
}
