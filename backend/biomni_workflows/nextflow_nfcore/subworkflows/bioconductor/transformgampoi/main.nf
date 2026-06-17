#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: transformGamPoi — delta_method_transformation
// Apply delta method-based transformations (acosh or shifted logarithm) to stabilize the variance of count data.
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
//  * 2. [Core Analysis] Apply the acosh transformation to the count matrix or SingleCellExperiment object
//  * 3. [Core Analysis] Alternatively, apply the shifted log transformation with a specified pseudo-count

nextflow.enable.dsl = 2

process BIOC_TRANSFORMGAMPOI_DELTA_METHOD_TRANSFORMATION {
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
    .bm_deps <- c("transformGamPoi", "MatrixGenerics", "SummarizedExperiment")
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
        library(transformGamPoi)
        library(SummarizedExperiment)
        library(MatrixGenerics)
        
        # 1. Load the data from the specified user input file
        if (!file.exists("counts_matrix.csv")) {
          stop("Error: 'counts_matrix.csv' not found in the working directory.")
        }
        
        # Read the raw count matrix
        counts_data <- as.matrix(read.csv("counts_matrix.csv", row.names = 1, check.names = FALSE))
        
        # Construct the SingleCellExperiment object
        sce <- SingleCellExperiment(assays = list(counts = counts_data))
        
        # Filter out genes with zero mean expression to avoid downstream issues
        gene_means <- rowMeans2(assay(sce, "counts"))
        sce <- sce[gene_means > 0, ]
        gene_means <- rowMeans2(assay(sce, "counts"))
        
        # 2. Apply the acosh transformation to the count matrix or SingleCellExperiment object
        # (Using the exact documented code syntax)
        assay(sce, "acosh") <- acosh_transform(assay(sce, "counts"))
        
        # 3. Alternatively, apply the shifted log transformation with a specified pseudo-count
        assay(sce, "shifted_log") <- shifted_log_transform(assay(sce, "counts"), pseudo_count = 1/(4 * 0.1))
        
        # Define the input range x as shown in the documentation
        x <- seq(0, 30, length.out = 1000)
        
        # Apply transformations using the exact documented function calls
        y_acosh <- acosh_transform(x, overdispersion = 0.1)
        y_shiftLog <- shifted_log_transform(x, pseudo_count = 1/(4 * 0.1))
        y_sqrt <- 2 * sqrt(x)
        
        # 4. Write meaningful output files
        # Save the transformed SingleCellExperiment object
        saveRDS(sce, "transformed_sce.rds")
        
        # Save the acosh-transformed counts as a CSV
        write.csv(as.matrix(assay(sce, "acosh")), "acosh_transformed_counts.csv", row.names = TRUE)
        
        # Save the comparison of transformations as a CSV
        transformation_comparison <- data.frame(
          input_x = x,
          acosh_transformed = y_acosh,
          shifted_log_transformed = y_shiftLog,
          sqrt_transformed = y_sqrt
        )
        write.csv(transformation_comparison, "transformation_comparison.csv", row.names = FALSE)
        
        # Generate diagnostic plots
        pdf("variance_stabilization_plots.pdf", width = 12, height = 6)
        par(mfrow = c(1, 2))
        
        # Plot 1: Log expression vs variance of acosh stabilized values
        acosh_var <- rowVars(assay(sce, "acosh"))
        plot(gene_means, acosh_var, log = "x", 
             main = "Log expression vs variance of acosh stabilized values",
             xlab = "Gene Means", ylab = "Variance of acosh values", col = "blue", pch = 16)
        abline(h = 1, col = "red", lty = 2, lwd = 2)
        
        # Plot 2: Comparison of delta method-based transformations
        plot(x, y_acosh, type = "l", col = "black", lwd = 3, 
             ylab = "g(x)", xlab = "x", ylim = c(0, 10),
             main = "Comparison of Transformations")
        lines(x, y_shiftLog, col = "red", lwd = 3)
        lines(x, y_sqrt, col = "blue", lwd = 3)
        legend("bottomright", 
               legend = c(expression(2*sqrt(x)), 
                          expression(1/sqrt(alpha)~acosh(2*alpha*x+1)),
                          expression(1/sqrt(alpha)~log(x+1/(4*alpha))+b)),
               col = c("blue", "black", "red"), lty = 1, inset = 0.05, lwd = 3)
        
        dev.off()
        
        message("Pipeline completed successfully. Outputs saved to 'transformed_sce.rds', 'acosh_transformed_counts.csv', 'transformation_comparison.csv', and 'variance_stabilization_plots.pdf'.")

    writeLines(c(
        '"BIOC_TRANSFORMGAMPOI_DELTA_METHOD_TRANSFORMATION":',
        paste0('    transformGamPoi: ', as.character(packageVersion('transformGamPoi')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_delta_method_transformation.csv versions.yml
    """
}

workflow BIOC_TRANSFORMGAMPOI_DELTA_METHOD_TRANSFORMATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ counts_matrix.csv ] ]

    main:
    BIOC_TRANSFORMGAMPOI_DELTA_METHOD_TRANSFORMATION(ch_input)

    emit:
    tables   = BIOC_TRANSFORMGAMPOI_DELTA_METHOD_TRANSFORMATION.out.tables
    plots    = BIOC_TRANSFORMGAMPOI_DELTA_METHOD_TRANSFORMATION.out.plots
    objects  = BIOC_TRANSFORMGAMPOI_DELTA_METHOD_TRANSFORMATION.out.objects
    versions = BIOC_TRANSFORMGAMPOI_DELTA_METHOD_TRANSFORMATION.out.versions
}
