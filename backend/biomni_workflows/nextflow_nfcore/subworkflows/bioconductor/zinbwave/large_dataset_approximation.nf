#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: zinbwave — large_dataset_approximation
// Perform fast, approximate dimensionality reduction on large single-cell datasets using the zinbsurf projection strategy.
// Input: SummarizedExperiment_object.rds
// Container: quay.io/biocontainers/bioconductor-zinbwave:1.32.0--r45hdfd78af_0
// Requires: BiocParallel, SingleCellExperiment, SummarizedExperiment, ggplot2, magrittr, zinbwave
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run zinbsurf specifying the proportion of cells to use for the initial model fit. 2. Extract the low-dimensional representation (W

nextflow.enable.dsl = 2

process BIOC_ZINBWAVE_LARGE_DATASET_APPROXIMATION {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load required libraries
    library(zinbwave)
    library(SummarizedExperiment)
    library(SingleCellExperiment)
    library(ggplot2)
    library(magrittr)
    library(BiocParallel)
    
    # Register BiocParallel Serial Execution for stability and reproducibility
    BiocParallel::register(BiocParallel::SerialParam())
    
    # 1. Read the user input file
    input_file <- "SummarizedExperiment_object.rds"
    if (!file.exists(input_file)) {
      stop(paste("Input file", input_file, "not found in the working directory."))
    }
    
    fluidigm <- readRDS(input_file)
    
    # Ensure the first assay is named "counts" as expected by zinbwave/zinbsurf
    if (!"counts" %in% assayNames(fluidigm)) {
      assayNames(fluidigm)[1] <- "counts"
    }
    
    # 2. Run zinbsurf specifying the proportion of cells to use for the initial model fit
    fluidigm_surf <- zinbsurf(fluidigm, K = 2, epsilon = 1000, prop_fit = 0.5)
    
    # 3. Extract the low-dimensional representation (W matrix) projected for all cells
    W2 <- reducedDim(fluidigm_surf)
    
    # 4. Save the outputs
    # Save the low-dimensional representation matrix as a CSV table
    write.csv(as.data.frame(W2), "zinbsurf_W2_representation.csv", row.names = TRUE)
    
    # Save the full SingleCellExperiment object containing the surf results
    saveRDS(fluidigm_surf, "fluidigm_surf_output.rds")
    
    # Generate and save the visualization plot
    pdf("zinbsurf_representation_plot.pdf", width = 7, height = 6)
    
    df_plot <- as.data.frame(W2)
    if (ncol(df_plot) >= 2) {
      colnames(df_plot)[1:2] <- c("W1", "W2")
      
      # Check if metadata columns from the vignette are present for coloring/shaping
      has_bio <- "Biological_Condition" %in% colnames(colData(fluidigm))
      has_cov <- "Coverage_Type" %in% colnames(colData(fluidigm))
      
      if (has_bio && has_cov) {
        df_plot\$bio <- colData(fluidigm)\$Biological_Condition
        df_plot\$coverage <- colData(fluidigm)\$Coverage_Type
        
        p <- ggplot(df_plot, aes(x = W1, y = W2, colour = bio, shape = coverage)) +
          geom_point(size = 2) +
          scale_color_brewer(type = "qual", palette = "Set1") +
          theme_classic() +
          labs(title = "ZINB-surf Low-Dimensional Representation",
               x = "W1", y = "W2")
      } else if (has_bio) {
        df_plot\$bio <- colData(fluidigm)\$Biological_Condition
        p <- ggplot(df_plot, aes(x = W1, y = W2, colour = bio)) +
          geom_point(size = 2) +
          scale_color_brewer(type = "qual", palette = "Set1") +
          theme_classic() +
          labs(title = "ZINB-surf Low-Dimensional Representation",
               x = "W1", y = "W2")
      } else {
        p <- ggplot(df_plot, aes(x = W1, y = W2)) +
          geom_point(size = 2, color = "blue") +
          theme_classic() +
          labs(title = "ZINB-surf Low-Dimensional Representation",
               x = "W1", y = "W2")
      }
      print(p)
    } else {
      warning("W2 matrix has fewer than 2 dimensions; skipping plot generation.")
    }
    
    dev.off()

    writeLines(c(
        '"BIOC_ZINBWAVE_LARGE_DATASET_APPROXIMATION":',
        paste0('    zinbwave: ', as.character(packageVersion('zinbwave')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_large_dataset_approximation.csv versions.yml
    """
}

workflow BIOC_ZINBWAVE_LARGE_DATASET_APPROXIMATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ SummarizedExperiment_object.rds ] ]

    main:
    BIOC_ZINBWAVE_LARGE_DATASET_APPROXIMATION(ch_input)

    emit:
    tables   = BIOC_ZINBWAVE_LARGE_DATASET_APPROXIMATION.out.tables
    plots    = BIOC_ZINBWAVE_LARGE_DATASET_APPROXIMATION.out.plots
    objects  = BIOC_ZINBWAVE_LARGE_DATASET_APPROXIMATION.out.objects
    versions = BIOC_ZINBWAVE_LARGE_DATASET_APPROXIMATION.out.versions
}
