#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: NewWave — scrna_dimensionality_reduction_batch_correction
// Perform dimensionality reduction and batch effect correction on raw scRNA-seq count data using NewWave, followed by latent space extraction.
// Input: data
// Container: quay.io/biocontainers/bioconductor-newwave:1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: NewWave, Rtsne, SingleCellExperiment, ggplot2
// Visualizations: t-SNE plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Convert the batch covariate to a factor
//  * 2. [Core Analysis] Run newWave to perform dimensionality reduction and batch correction (using standard, parallelized, or mini-batch configurations)
//  * 3. [Core Analysis] Extract the low-dimensional latent representation using reducedDim

nextflow.enable.dsl = 2

process BIOC_NEWWAVE_SCRNA_DIMENSIONALITY_REDUCTION_BATCH_CORRECTION {
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
    .bm_deps <- c("NewWave", "Rtsne", "ggplot2", "SummarizedExperiment")
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
        
    # Load required librari    library(SummarizedExperiment)
es
    library(NewWave)
    library(Rtsne)
    library(ggplot2)
    
    # Read the input SingleCellExperiment object from the working directory
    if (!file.exists("data.rds")) {
      stop("Error: Input file 'data.rds' not found in the working directory.")
    }
    data <- readRDS("data.rds")
    
    # Ensure the Batch covariate exists and is correctly named
    if (!"Batch" %in% colnames(colData(data))) {
      if ("batch" %in% colnames(colData(data))) {
        data\$Batch <- data\$batch
      } else {
        stop("Error: The input SingleCellExperiment object must contain a 'Batch' or 'batch' covariate in colData.")
      }
    }
    
    # 1. Convert the batch covariate to a factor
    data\$Batch <- as.factor(data\$Batch)
    
    # 2. Run newWave to perform dimensionality reduction and batch correction
    # Using parallelized usage for better performance
    message("Running parallelized NewWave (children=2)...")
    res <- newWave(data, X = "~Batch", K=10, verbose = TRUE, children=2)
    
    # 3. Extract the low-dimensional latent representation
    latent <- reducedDim(res)
    
    # Save the results to the working directory
    saveRDS(res, "newwave_res.rds")
    write.csv(latent, "latent_representation.csv", row.names = TRUE)
    
    # Generate and save a t-SNE visualization of the latent space
    message("Generating t-SNE visualization of the latent space...")
    tsne_latent <- data.frame(Rtsne(latent)\$Y)
    colnames(tsne_latent) <- c("X1", "X2")
    tsne_latent\$batch <- data\$Batch
    
    if ("Group" %in% colnames(colData(data))) {
      tsne_latent\$group <- data\$Group
      p <- ggplot(tsne_latent, aes(x=X1, y=X2, col=group, shape=batch)) + 
        geom_point(alpha=0.8) +
        theme_minimal() +
        labs(title = "t-SNE of NewWave Latent Space", x = "t-SNE 1", y = "t-SNE 2")
    } else {
      p <- ggplot(tsne_latent, aes(x=X1, y=X2, col=batch)) + 
        geom_point(alpha=0.8) +
        theme_minimal() +
        labs(title = "t-SNE of NewWave Latent Space", x = "t-SNE 1", y = "t-SNE 2")
    }
    
    ggsave("latent_tsne_plot.pdf", plot = p, width = 7, height = 6)
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_NEWWAVE_SCRNA_DIMENSIONALITY_REDUCTION_BATCH_CORRECTION":',
        paste0('    NewWave: ', as.character(packageVersion('NewWave')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scrna_dimensionality_reduction_batch_correction.csv versions.yml
    """
}

workflow BIOC_NEWWAVE_SCRNA_DIMENSIONALITY_REDUCTION_BATCH_CORRECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ data ] ]

    main:
    BIOC_NEWWAVE_SCRNA_DIMENSIONALITY_REDUCTION_BATCH_CORRECTION(ch_input)

    emit:
    tables   = BIOC_NEWWAVE_SCRNA_DIMENSIONALITY_REDUCTION_BATCH_CORRECTION.out.tables
    plots    = BIOC_NEWWAVE_SCRNA_DIMENSIONALITY_REDUCTION_BATCH_CORRECTION.out.plots
    objects  = BIOC_NEWWAVE_SCRNA_DIMENSIONALITY_REDUCTION_BATCH_CORRECTION.out.objects
    versions = BIOC_NEWWAVE_SCRNA_DIMENSIONALITY_REDUCTION_BATCH_CORRECTION.out.versions
}
