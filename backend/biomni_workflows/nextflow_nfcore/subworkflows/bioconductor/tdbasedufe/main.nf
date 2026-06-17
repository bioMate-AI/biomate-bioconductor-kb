#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: TDbasedUFE — single_omics_gene_expression
// Extract key genes from a single-modality gene expression dataset using HOSVD tensor decomposition.
// Input: gene_expression_counts.csv, sample_metadata.csv
// Container: quay.io/biocontainers/bioconductor-tdbasedufe:1.10.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: TDbasedUFE, rTensor
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Reformat the expression data into a multi-dimensional
//  * 2. [Core Analysis] Apply Higher-Order Singular Value Decomposition (HOSVD)
//  * 3. [Core Analysis] Select the singular value vectors representing the
//  * 4. [Core Analysis] Perform feature selection based on the selected vectors
//  * 5. [Core Analysis] Extract and view the top-ranked features

nextflow.enable.dsl = 2

process BIOC_TDBASEDUFE_SINGLE_OMICS_GENE_EXPRESSION {
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
    .bm_deps <- c("TDbasedUFE", "rTensor")
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
            library(TDbasedUFE)
            library(rTensor)
            
            # Check if input files exist
            if (!file.exists("gene_expression_counts.csv") || !file.exists("sample_metadata.csv")) {
              stop("Required input files 'gene_expression_counts.csv' and/or 'sample_metadata.csv' are missing.")
            }
            
            # Read user inputs
            counts_df <- read.csv("gene_expression_counts.csv", row.names = 1, check.names = FALSE)
            samples <- read.csv("sample_metadata.csv", stringsAsFactors = FALSE)
            
            # Ensure samples\$sample exists and matches the columns of counts_df
            if (!"sample" %in% colnames(samples)) {
              # Try to find a column that matches counts_df columns, or just use the first column
              matching_col <- sapply(samples, function(col) all(col %in% colnames(counts_df)))
              if (any(matching_col)) {
                samples\$sample <- samples[[which(matching_col)[1]]]
              } else {
                samples\$sample <- colnames(counts_df)[1:nrow(samples)]
              }
            }
            
            # Ensure samples\$condition exists
            if (!"condition" %in% colnames(samples)) {
              # Try to find a column that represents the experimental condition
              potential_cols <- setdiff(colnames(samples), "sample")
              if (length(potential_cols) > 0) {
                samples\$condition <- samples[[potential_cols[1]]]
              } else {
                samples\$condition <- "A"
              }
            }
            
            # Sort samples by condition to group replicates together for the tensor
            samples <- samples[order(samples\$condition), ]
            
            # Subset and order counts_matrix to match samples
            common_samples <- intersect(samples\$sample, colnames(counts_df))
            if (length(common_samples) == 0) {
              stop("No matching samples found between metadata and counts matrix.")
            }
            samples <- samples[samples\$sample %in% common_samples, ]
            
            counts_matrix <- as.matrix(counts_df)
            counts_matrix <- counts_matrix[, samples\$sample, drop = FALSE]
            
            # Dynamically determine dimensions from the metadata
            num_conditions <- length(unique(samples\$condition))
            num_replicates <- nrow(samples) / num_conditions
            
            if (nrow(samples) %% num_conditions != 0) {
              stop("The number of samples must be perfectly divisible by the number of conditions for a balanced tensor.")
            }
            
            # Construct txi object
            txi <- list(
              counts = counts_matrix,
              abundance = counts_matrix
            )
            
            # Open PDF device to capture plots
            pdf("TDbasedUFE_plots.pdf", width = 10, height = 7)
            
            # --- Reformat the expression data into a multi-dimensional ---
            Z <- PrepareSummarizedExperimentTensor(
              matrix(samples\$sample, nrow = num_replicates, ncol = num_conditions), 
              rownames(txi\$abundance),
              array(txi\$counts, c(dim(txi\$counts)[1], num_replicates, num_conditions))
            )
            
            # Save Z object
            saveRDS(Z, "tensor_Z.rds")
            
            # --- Apply Higher-Order Singular Value Decomposition (HOSVD) ---
            HOSVD <- computeHosvd(Z)
            
            # Save HOSVD object
            saveRDS(HOSVD, "hosvd_results.rds")
            
            # --- Select the singular value vectors representing the ---
            # Mode 2 (replicates): constant vector (1)
            # Mode 3 (conditions): distinction vector (2)
            sv_conditions <- if (num_conditions > 1) 2 else 1
            input_all <- selectSingularValueVectorSmall(HOSVD, input_all = c(1, sv_conditions))
            
            # --- Perform feature selection based on the selected vectors ---
            index <- selectFeature(HOSVD, input_all)
            
            # Save index object
            saveRDS(index, "feature_index.rds")
            
            # Close PDF device
            dev.off()
            
            # --- Extract and view the top-ranked features ---
            feature_table <- tableFeatures(Z, index)
            
            # Save the feature table to CSV
            write.csv(feature_table, "selected_features.csv", row.names = FALSE)
            
            # Print the head of the table to stdout
            print(head(feature_table))

    writeLines(c(
        '"BIOC_TDBASEDUFE_SINGLE_OMICS_GENE_EXPRESSION":',
        paste0('    TDbasedUFE: ', as.character(packageVersion('TDbasedUFE')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_omics_gene_expression.csv versions.yml
    """
}

workflow BIOC_TDBASEDUFE_SINGLE_OMICS_GENE_EXPRESSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gene_expression_counts.csv, sample_metadata.csv ] ]

    main:
    BIOC_TDBASEDUFE_SINGLE_OMICS_GENE_EXPRESSION(ch_input)

    emit:
    tables   = BIOC_TDBASEDUFE_SINGLE_OMICS_GENE_EXPRESSION.out.tables
    plots    = BIOC_TDBASEDUFE_SINGLE_OMICS_GENE_EXPRESSION.out.plots
    objects  = BIOC_TDBASEDUFE_SINGLE_OMICS_GENE_EXPRESSION.out.objects
    versions = BIOC_TDBASEDUFE_SINGLE_OMICS_GENE_EXPRESSION.out.versions
}
