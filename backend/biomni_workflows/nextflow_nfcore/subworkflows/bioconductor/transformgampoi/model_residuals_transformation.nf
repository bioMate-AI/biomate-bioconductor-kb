#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: transformGamPoi — model_residuals_transformation
// Apply model residuals-based transformations (Pearson or randomized quantile residuals) to stabilize variance across all genes, including lowly expressed ones.
// Input: counts_matrix.csv
// Container: quay.io/biocontainers/bioconductor-transformgampoi:1.16.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MatrixGenerics, SingleCellExperiment, transformGamPoi
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the package and data
//  * 2. [Core Analysis] Apply the Pearson residuals transformation with clipping
//  * 3. [Core Analysis] Alternatively, apply the randomized quantile residuals transformation to handle non-linear variance stabilization and discrete cou

nextflow.enable.dsl = 2

process BIOC_TRANSFORMGAMPOI_MODEL_RESIDUALS_TRANSFORMATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    library(transformGamPoi)
    library(MatrixGenerics)
    
    # 1. Load the data from the user-specified input file
    input_file <- "counts_matrix.csv"
    if (!file.exists(input_file)) {
      stop(paste("Required input file missing:", input_file))
    }
    
    # Read counts matrix (assuming genes as rows, cells as columns, first column as gene IDs)
    counts_df <- read.csv(input_file, row.names = 1, check.names = FALSE)
    counts_mat <- as.matrix(counts_df)
    
    # Construct SingleCellExperiment object
    sce <- SingleCellExperiment(assays = list(counts = counts_mat))
    
    # Filter out genes with zero counts across all cells to avoid downstream issues
    # (similar to the vignette's filtering step)
    sce <- sce[rowMeans2(assay(sce, "counts")) > 0, ]
    
    # Calculate gene means for plotting later
    gene_means <- rowMeans2(assay(sce, "counts"))
    
    # 2. Apply the Pearson residuals transformation with clipping
    assay(sce, "pearson") <- residual_transform(sce, "pearson", clipping = TRUE, on_disk = FALSE)
    
    # 3. Alternatively, apply the randomized quantile residuals transformation
    assay(sce, "rand_quantile") <- residual_transform(sce, "randomized_quantile", on_disk = FALSE)
    
    # Save the transformed SingleCellExperiment object
    saveRDS(sce, "transformed_sce.rds")
    
    # Save the transformed matrices as CSV files
    write.csv(as.matrix(assay(sce, "pearson")), "pearson_residuals.csv", row.names = TRUE)
    write.csv(as.matrix(assay(sce, "rand_quantile")), "randomized_quantile_residuals.csv", row.names = TRUE)
    
    # Generate diagnostic plots
    pdf("residual_variance_plots.pdf", width = 12, height = 6)
    par(mfrow = c(1, 2))
    
    # Plot Pearson residuals variance
    pearson_var <- rowVars(assay(sce, "pearson"))
    plot(gene_means, pearson_var, log = "x", 
         main = "Log expression vs variance of Pearson residuals",
         xlab = "Gene Means", ylab = "Variance of Pearson Residuals",
         col = "blue", pch = 16, cex = 0.6)
    abline(h = 1, col = "red", lwd = 2)
    
    # Plot Randomized Quantile residuals variance
    rand_quant_var <- rowVars(assay(sce, "rand_quantile"))
    plot(gene_means, rand_quant_var, log = "x", 
         main = "Log expression vs variance of Randomized Quantile residuals",
         xlab = "Gene Means", ylab = "Variance of Randomized Quantile Residuals",
         col = "darkgreen", pch = 16, cex = 0.6)
    abline(h = 1, col = "red", lwd = 2)
    
    dev.off()
    
    message("Workflow completed successfully. Outputs saved: transformed_sce.rds, pearson_residuals.csv, randomized_quantile_residuals.csv, residual_variance_plots.pdf")

    writeLines(c(
        '"BIOC_TRANSFORMGAMPOI_MODEL_RESIDUALS_TRANSFORMATION":',
        paste0('    transformGamPoi: ', as.character(packageVersion('transformGamPoi')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_model_residuals_transformation.csv versions.yml
    """
}

workflow BIOC_TRANSFORMGAMPOI_MODEL_RESIDUALS_TRANSFORMATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ counts_matrix.csv ] ]

    main:
    BIOC_TRANSFORMGAMPOI_MODEL_RESIDUALS_TRANSFORMATION(ch_input)

    emit:
    tables   = BIOC_TRANSFORMGAMPOI_MODEL_RESIDUALS_TRANSFORMATION.out.tables
    plots    = BIOC_TRANSFORMGAMPOI_MODEL_RESIDUALS_TRANSFORMATION.out.plots
    objects  = BIOC_TRANSFORMGAMPOI_MODEL_RESIDUALS_TRANSFORMATION.out.objects
    versions = BIOC_TRANSFORMGAMPOI_MODEL_RESIDUALS_TRANSFORMATION.out.versions
}
