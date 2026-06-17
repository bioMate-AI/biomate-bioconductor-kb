#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: alabaster_matrix — alabaster_matrix_roundtrip_pca
// Read a feature-by-sample matrix, serialize it to disk using alabaster.matrix representations (dense and sparse), deserialize it back to verify integrity, and pe
// Input: input.csv
// Container: quay.io/biocontainers/r-base:4.3.1
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: DelayedArray, Matrix, alabaster.base, alabaster.matrix, alabaster_matrix
// Visualizations: PCA plot
// QC: input validation
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ALABASTER_MATRIX_ALABASTER_MATRIX_ROUNDTRIP_PCA {
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
    .bm_deps <- c("alabaster.base", "alabaster.matrix", "Matrix", "DelayedArray")
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
    
    # --- Load required libraries and read input defensively ---
    library(alabaster.base)
    library(alabaster.matrix)
    library(Matrix)
    library(DelayedArray)
    
    # Read input.csv defensively
    if (!file.exists("input.csv")) {
      stop("Error: input.csv not found in the working directory.")
    }
    
    df <- read.csv("input.csv", check.names = FALSE, stringsAsFactors = FALSE)
    
    # Determine row names from 'feature_id' or the first column
    if ("feature_id" %in% colnames(df)) {
      row_names <- df\$feature_id
      df\$feature_id <- NULL
    } else {
      row_names <- df[, 1]
      df <- df[, -1, drop = FALSE]
    }
    
    # Convert remaining columns to a numeric matrix
    mat <- as.matrix(df)
    class(mat) <- "numeric"
    rownames(mat) <- row_names
    
    # Handle potential missing values or non-numeric artifacts safely
    mat[is.na(mat)] <- 0
    
    message(sprintf("Successfully loaded matrix with %d features and %d samples.", nrow(mat), ncol(mat)))
    
    # --- Convert to different matrix representations ---
    # alabaster.matrix supports standard R matrices, sparse matrices, and DelayedMatrices
    dense_mat <- mat
    sparse_mat <- as(mat, "CsparseMatrix") # dgCMatrix representation
    delayed_mat <- DelayedArray(mat)
    
    # --- Serialize matrices to disk using alabaster.base / ---
    # We create temporary directories to store the serialized artifacts
    stage_dir_dense <- tempfile("stage_dense")
    stage_dir_sparse <- tempfile("stage_sparse")
    
    message("Saving dense matrix to: ", stage_dir_dense)
    alabaster.base::saveObject(dense_mat, stage_dir_dense)
    
    message("Saving sparse matrix to: ", stage_dir_sparse)
    alabaster.base::saveObject(sparse_mat, stage_dir_sparse)
    
    # --- Deserialize matrices back to verify round-trip fidelity ---
    message("Reading objects back from disk...")
    roundtrip_dense <- alabaster.base::readObject(stage_dir_dense)
    roundtrip_sparse <- alabaster.base::readObject(stage_dir_sparse)
    
    # Verify that the round-tripped matrices match the original data
    stopifnot(all.equal(as.matrix(roundtrip_dense), mat, check.attributes = FALSE))
    stopifnot(all.equal(as.matrix(roundtrip_sparse), mat, check.attributes = FALSE))
    message("Fidelity check passed: Round-tripped matrices are identical to the original input.")
    
    # --- Downstream Analysis (PCA) on the restored matrix ---
    # We perform PCA on the restored dense matrix representation
    pca_coords <- tryCatch({
      # Filter out zero-variance features to avoid PCA errors
      vars <- apply(roundtrip_dense, 1, var)
      keep <- !is.na(vars) & vars > 0
      filtered_mat <- roundtrip_dense[keep, , drop = FALSE]
      
      if (nrow(filtered_mat) >= 2 && ncol(filtered_mat) >= 2) {
        # Perform PCA on transposed matrix (samples as rows, features as columns)
        pca <- prcomp(t(filtered_mat), scale. = TRUE)
        pcs <- as.data.frame(pca\$x[, 1:min(2, ncol(pca\$x)), drop = FALSE])
        # Ensure we have both PC1 and PC2 columns
        if (ncol(pcs) < 2) {
          pcs\$PC2 <- 0
        }
        colnames(pcs)[1:2] <- c("PC1", "PC2")
        pcs
      } else {
        stop("Not enough features or samples with variance for PCA.")
      }
    }, error = function(e) {
      warning("PCA failed, falling back to summary statistics: ", e\$message)
      # Fallback: use column means and column sums as proxy coordinates
      data.frame(
        PC1 = colMeans(roundtrip_dense),
        PC2 = colSums(roundtrip_dense),
        row.names = colnames(roundtrip_dense)
      )
    })
    
    # Add sample names explicitly to the output
    pca_coords\$sample_id <- rownames(pca_coords)
    pca_coords <- pca_coords[, c("sample_id", "PC1", "PC2")]
    
    # --- Write outputs to the working directory ---
    write.csv(pca_coords, "pca_results.csv", row.names = FALSE)
    message("Saved PCA results to pca_results.csv")
    
    # Generate diagnostic visualization
    pdf("pca_plot.pdf", width = 7, height = 7)
    plot(
      pca_coords\$PC1, 
      pca_coords\$PC2, 
      xlab = "PC1 / Column Mean (Fallback)", 
      ylab = "PC2 / Column Sum (Fallback)", 
      main = "Sample Projection (alabaster.matrix Round-trip)",
      col = "royalblue", 
      pch = 19, 
      cex = 1.5
    )
    text(
      pca_coords\$PC1, 
      pca_coords\$PC2, 
      labels = pca_coords\$sample_id, 
      pos = 3, 
      cex = 0.8, 
      col = "darkgray"
    )
    grid()
    dev.off()
    message("Saved PCA plot to pca_plot.pdf")

    writeLines(c(
        '"BIOC_ALABASTER_MATRIX_ALABASTER_MATRIX_ROUNDTRIP_PCA":',
        paste0('    alabaster_matrix: ', as.character(packageVersion('alabaster_matrix')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_alabaster_matrix_roundtrip_pca.csv versions.yml
    """
}

workflow BIOC_ALABASTER_MATRIX_ALABASTER_MATRIX_ROUNDTRIP_PCA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_ALABASTER_MATRIX_ALABASTER_MATRIX_ROUNDTRIP_PCA(ch_input)

    emit:
    tables   = BIOC_ALABASTER_MATRIX_ALABASTER_MATRIX_ROUNDTRIP_PCA.out.tables
    plots    = BIOC_ALABASTER_MATRIX_ALABASTER_MATRIX_ROUNDTRIP_PCA.out.plots
    objects  = BIOC_ALABASTER_MATRIX_ALABASTER_MATRIX_ROUNDTRIP_PCA.out.objects
    versions = BIOC_ALABASTER_MATRIX_ALABASTER_MATRIX_ROUNDTRIP_PCA.out.versions
}
