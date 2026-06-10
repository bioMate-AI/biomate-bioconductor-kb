#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SPEM — entire_network_reconstruction
// Reconstruct the entire gene regulatory network parameters (alpha, G, beta, H) from a time-series ExpressionSet.
// Input: user_expression_data.csv, user_timepoints_metadata.csv
// Container: quay.io/biocontainers/bioconductor-spem:1.50.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, Rsolnp, SPEM
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Prepare the expression matrix and phenoData
//  * 2. [Input & Preparation] Create an ExpressionSet object
//  * 3. [Core Analysis] Set optimization parameters (n, sparsity, boundaries)
//  * 4. [Core Analysis] Run the main SPEM function to estimate all parameters

nextflow.enable.dsl = 2

process BIOC_SPEM_ENTIRE_NETWORK_RECONSTRUCTION {
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
    library(SPEM)
    library(Rsolnp)
    library(Biobase)
    
    # Set seed for reproducibility of the random beta generation
    set.seed(42)
    
    # Read user input files
    expr_df <- read.csv("user_expression_data.csv", row.names = 1, check.names = FALSE)
    expr_matrix <- as.matrix(expr_df)
    
    tp_df <- read.csv("user_timepoints_metadata.csv", row.names = 1, check.names = FALSE)
    
    # Align samples between expression matrix and metadata
    common_samples <- intersect(colnames(expr_matrix), rownames(tp_df))
    if (length(common_samples) == 0) {
      stop("Error: No matching samples found between expression data columns and metadata rows.")
    }
    expr_matrix <- expr_matrix[, common_samples, drop = FALSE]
    tp_df <- tp_df[common_samples, , drop = FALSE]
    
    # Ensure 'time' column exists in metadata
    if (!"time" %in% colnames(tp_df)) {
      stop("Error: Metadata must contain a 'time' column specifying exact time points.")
    }
    
    # Construct AnnotatedDataFrame for phenoData
    var_meta <- data.frame(
      labelDescription = paste("Metadata for", colnames(tp_df)),
      row.names = colnames(tp_df)
    )
    pheno_data <- new("AnnotatedDataFrame", data = tp_df, varMetadata = var_meta)
    
    # Construct the ExpressionSet named 'sos' as required by the documented code
    sos <- new("ExpressionSet", exprs = expr_matrix, phenoData = pheno_data)
    
    # --- DOCUMENTED CODE WORKFLOW ---
    Slope <- s_diff(sos)
    n <- 1
    sparsity <- 0.2
    lbH <- -3
    ubH <- 3
    lbB <- 0
    ubB <- 10
    result <- SPEM(sos, n, sparsity, lbH, ubH, lbB, ubB)
    # --- END DOCUMENTED CODE WORKFLOW ---
    
    # Save outputs
    write.csv(as.matrix(Slope), "calculated_slopes.csv", row.names = TRUE)
    saveRDS(result, "SPEM_result.rds")
    
    # Write summary of optimization results
    sink("SPEM_summary.txt")
    cat("=== SPEM Results ===\n")
    print(result)
    sink()
    
    # Generate visualization of expression and calculated slope for the target gene
    pdf("gene_expression_and_slope.pdf", width = 7, height = 10)
    par(mfrow = c(2, 1))
    gene_name <- rownames(sos)[1]
    time_points <- pData(sos)\$time
    plot(time_points, exprs(sos)[1, ], type = "b", pch = 19, col = "blue",
         main = paste("Expression Profile:", gene_name), xlab = "Time", ylab = "Expression Level")
    plot(time_points, Slope[1, ], type = "b", pch = 19, col = "red",
         main = paste("Calculated Slope:", gene_name), xlab = "Time", ylab = "Slope (d/dt)")
    dev.off()

    writeLines(c(
        '"BIOC_SPEM_ENTIRE_NETWORK_RECONSTRUCTION":',
        paste0('    SPEM: ', as.character(packageVersion('SPEM')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_entire_network_reconstruction.csv versions.yml
    """
}

workflow BIOC_SPEM_ENTIRE_NETWORK_RECONSTRUCTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ user_expression_data.csv, user_timepoints_metadata.csv ] ]

    main:
    BIOC_SPEM_ENTIRE_NETWORK_RECONSTRUCTION(ch_input)

    emit:
    tables   = BIOC_SPEM_ENTIRE_NETWORK_RECONSTRUCTION.out.tables
    plots    = BIOC_SPEM_ENTIRE_NETWORK_RECONSTRUCTION.out.plots
    objects  = BIOC_SPEM_ENTIRE_NETWORK_RECONSTRUCTION.out.objects
    versions = BIOC_SPEM_ENTIRE_NETWORK_RECONSTRUCTION.out.versions
}
