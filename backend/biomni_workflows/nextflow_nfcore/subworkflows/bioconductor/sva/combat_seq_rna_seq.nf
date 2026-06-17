#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: sva — combat_seq_rna_seq
// Adjust for known batch effects in RNA-Seq count data using a negative binomial model while preserving integer counts and biological covariates.
// Input: raw_counts.csv, sample_metadata.csv
// Container: quay.io/biocontainers/bioconductor-sva:3.58.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: sva
// Visualizations: plot (ggplot/base)
// QC: batch-effect correction
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define the count matrix, batch vector, and biological covariates
//  * 2. [Core Analysis] Run ComBat_seq to obtain batch-adjusted integer counts

nextflow.enable.dsl = 2

process BIOC_SVA_COMBAT_SEQ_RNA_SEQ {
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
    .bm_deps <- c("sva")
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
            library(sva)
            
            # ==========================================
            # 1. Read User Input Files and Setup Data
            # ==========================================
            
            # Read raw integer RNA-Seq counts
            # Expects genes in rows and samples in columns
            counts_df <- read.csv("raw_counts.csv", row.names = 1, check.names = FALSE)
            count_matrix <- as.matrix(counts_df)
            
            # Ensure counts are integers
            storage.mode(count_matrix) <- "integer"
            
            # Read sample metadata
            metadata <- read.csv("sample_metadata.csv", row.names = 1, check.names = FALSE)
            
            # Align count matrix columns with metadata rows
            common_samples <- intersect(colnames(count_matrix), rownames(metadata))
            if (length(common_samples) == 0) {
              # If row names of metadata do not match, try using the first column as sample IDs
              rownames(metadata) <- metadata[, 1]
              common_samples <- intersect(colnames(count_matrix), rownames(metadata))
            }
            
            if (length(common_samples) == 0) {
              stop("Error: Could not align sample names between raw_counts.csv and sample_metadata.csv")
            }
            
            count_matrix <- count_matrix[, common_samples, drop = FALSE]
            metadata <- metadata[common_samples, , drop = FALSE]
            
            # Extract batch variable (look for "batch" column, case-insensitive)
            batch_col <- grep("^batch\$", colnames(metadata), ignore.case = TRUE, value = TRUE)
            if (length(batch_col) == 0) {
              stop("Error: 'batch' column not found in sample_metadata.csv")
            }
            batch <- metadata[[batch_col]]
            
            # Extract biological group covariate (look for "group", "condition", or "treatment")
            group_col <- grep("^(group|condition|treatment)\$", colnames(metadata), ignore.case = TRUE, value = TRUE)
            if (length(group_col) > 0) {
              group <- metadata[[group_col[1]]]
            } else {
              group <- NULL
            }
            
            # Extract other covariates for covar_mod (excluding batch and group columns)
            cov_cols <- setdiff(colnames(metadata), c(batch_col, group_col))
            if (length(cov_cols) > 0) {
              # Convert covariates to a numeric matrix/data frame as expected by ComBat_seq
              covar_df <- metadata[, cov_cols, drop = FALSE]
              # Use model.matrix to generate dummy variables for categorical covariates
              covar_mat <- model.matrix(~ ., data = covar_df)[, -1, drop = FALSE]
            } else {
              covar_mat <- NULL
            }
            
            # ==========================================
            # 2. Run ComBat_seq Batch Adjustments
            # ==========================================
            
            # Run ComBat_seq once with all intended covariates combined
            adjusted_counts <- ComBat_seq(count_matrix, batch=batch, group=group, covar_mod=covar_mat)
            
            # Save to the appropriate CSV name based on the covariates provided
            if (!is.null(covar_mat)) {
              write.csv(adjusted_counts, "adjusted_counts_with_covar.csv", row.names = TRUE)
            } else if (!is.null(group)) {
              write.csv(adjusted_counts, "adjusted_counts_with_group.csv", row.names = TRUE)
            } else {
              write.csv(adjusted_counts, "adjusted_counts_no_group.csv", row.names = TRUE)
            }
            
            # Save the final adjusted counts object
            saveRDS(adjusted_counts, "adjusted_counts.rds")
            
            # ==========================================
            # 3. Generate Diagnostic Plots
            # ==========================================
            
            # Helper function to plot PCA
            plot_pca <- function(counts, batch_vec, title) {
              # Log-transform counts for visualization
              log_counts <- log2(counts + 1)
              pca <- prcomp(t(log_counts))
              percentVar <- round(100 * pca\$sdev^2 / sum(pca\$sdev^2), 1)
              
              batch_factor <- as.factor(batch_vec)
              colors <- as.numeric(batch_factor)
              
              plot(pca\$x[, 1], pca\$x[, 2], col = colors, pch = 19, cex = 1.5,
                   xlab = paste0("PC1: ", percentVar[1], "% variance"),
                   ylab = paste0("PC2: ", percentVar[2], "% variance"),
                   main = title)
              legend("topright", legend = levels(batch_factor), col = 1:length(levels(batch_factor)), 
                     pch = 19, title = "Batch")
            }
            
            # Save PCA comparison plot to PDF
            pdf("batch_correction_plots.pdf", width = 12, height = 6)
            par(mfrow = c(1, 2))
            plot_pca(count_matrix, batch, "Before ComBat_seq")
            plot_pca(adjusted_counts, batch, "After ComBat_seq")
            dev.off()

    writeLines(c(
        '"BIOC_SVA_COMBAT_SEQ_RNA_SEQ":',
        paste0('    sva: ', as.character(packageVersion('sva')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_combat_seq_rna_seq.csv versions.yml
    """
}

workflow BIOC_SVA_COMBAT_SEQ_RNA_SEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ raw_counts.csv, sample_metadata.csv ] ]

    main:
    BIOC_SVA_COMBAT_SEQ_RNA_SEQ(ch_input)

    emit:
    tables   = BIOC_SVA_COMBAT_SEQ_RNA_SEQ.out.tables
    plots    = BIOC_SVA_COMBAT_SEQ_RNA_SEQ.out.plots
    objects  = BIOC_SVA_COMBAT_SEQ_RNA_SEQ.out.objects
    versions = BIOC_SVA_COMBAT_SEQ_RNA_SEQ.out.versions
}
