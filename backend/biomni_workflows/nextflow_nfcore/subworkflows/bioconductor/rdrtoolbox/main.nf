#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RDRToolbox — nonlinear_dimension_reduction
// Perform nonlinear dimension reduction using Isomap and LLE on transcriptomics data, estimate intrinsic dimensionality, validate clusters using the Davies-Bouldi
// Input: expression_matrix.csv, sample_metadata.csv
// Container: quay.io/biocontainers/bioconductor-rdrtoolbox:1.60.0--r45h575d39b_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: RDRToolbox
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Transpose the expression matrix to format it as N x D (samples x features)
//  * 2. [Visualization & Output] Estimate the intrinsic dimension of the dataset using Isomap with residual variance plotting
//  * 3. [Core Analysis] Perform Isomap dimension reduction to 2 dimensions
//  * 4. [Core Analysis] Perform LLE dimension reduction to 2 dimensions
//  * 5. [Core Analysis] Validate the quality of the resulting clusters using the Davies-Bouldin Index
//  * 6. [Visualization & Output] Visualize the low-dimensional embeddings using plotDR

nextflow.enable.dsl = 2

process BIOC_RDRTOOLBOX_NONLINEAR_DIMENSION_REDUCTION {
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
    .bm_deps <- c("RDRToolbox")
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
    library(RDRToolbox)
    
    # ==========================================
    # 1. Read and Preprocess User Input Files
    # ==========================================
    
    # Read the high-dimensional gene expression matrix (genes as rows, samples as columns)
    expr_mat <- read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE)
    
    # Read the sample metadata containing class labels
    metadata <- read.csv("sample_metadata.csv", row.names = 1, check.names = FALSE)
    
    # Align samples between expression matrix and metadata
    common_samples <- intersect(colnames(expr_mat), rownames(metadata))
    if (length(common_samples) == 0) {
      # Fallback if row names of metadata do not match column names of expression matrix
      # Assume first column of metadata contains sample IDs
      metadata_raw <- read.csv("sample_metadata.csv", check.names = FALSE)
      common_samples <- intersect(colnames(expr_mat), metadata_raw[[1]])
      rownames(metadata_raw) <- metadata_raw[[1]]
      metadata <- metadata_raw[common_samples, , drop = FALSE]
    }
    
    expr_mat <- expr_mat[, common_samples, drop = FALSE]
    metadata <- metadata[common_samples, , drop = FALSE]
    
    # Extract class labels
    # Look for common label column names, fallback to the first non-ID column
    label_col <- "class"
    if (!label_col %in% colnames(metadata)) {
      possible_cols <- colnames(metadata)[grepl("class|label|ALL.AML|type|group", colnames(metadata), ignore.case = TRUE)]
      if (length(possible_cols) > 0) {
        label_col <- possible_cols[1]
      } else {
        label_col <- colnames(metadata)[1]
        if (ncol(metadata) > 1) {
          label_col <- colnames(metadata)[2]
        }
      }
    }
    labels <- metadata[[label_col]]
    
    # Transpose the expression matrix to format it as N x D (samples x features)
    golubExprs = t(as.matrix(expr_mat))
    
    # Display dimensions and labels
    dim(golubExprs)
    show(labels)
    
    # ==========================================
    # 2. Estimate Intrinsic Dimensionality
    # ==========================================
    
    # Estimate the intrinsic dimension of the dataset using Isomap with residual variance plotting
    # Wrapped in tryCatch to handle cases where the input dataset has fewer samples than dimensions
    tryCatch({
      pdf("isomap_residual_variance.pdf")
      Isomap(data=golubExprs, dims=1:10, plotResiduals=TRUE, k=5)
      dev.off()
    }, error = function(e) {
      warning("Could not plot residual variance for dims 1:10: ", e\$message)
      if (dev.cur() > 1) dev.off()
    })
    
    # ==========================================
    # 3. Perform Dimension Reduction
    # ==========================================
    
    # Perform Isomap dimension reduction to 2 dimensions
    golubIsomap = Isomap(data=golubExprs, dims=2, k=5)
    
    # Perform LLE dimension reduction to 2 dimensions
    golubLLE = LLE(data=golubExprs, dim=2, k=5)
    
    # ==========================================
    # 4. Validate Clusters (Davies-Bouldin Index)
    # ==========================================
    
    # Validate the quality of the resulting clusters using the Davies-Bouldin Index
    db_isomap <- DBIndex(data=golubIsomap\$dim2, labels=labels)
    db_lle <- DBIndex(data=golubLLE, labels=labels)
    
    # Save validation results to a CSV file
    db_results <- data.frame(
      Method = c("Isomap", "LLE"),
      DBIndex = c(db_isomap, db_lle)
    )
    write.csv(db_results, "db_index_validation.csv", row.names = FALSE)
    
    # ==========================================
    # 5. Visualize Low-Dimensional Embeddings
    # ==========================================
    
    # Visualize the low-dimensional embeddings using plotDR and save to PDF
    pdf("dimension_reduction_plots.pdf", width = 12, height = 6)
    par(mfrow = c(1, 2))
    
    plotDR(data=golubIsomap\$dim2, labels=labels, axesLabels=c("", ""), legend=TRUE)
    title(main="Isomap")
    
    plotDR(data=golubLLE, labels=labels, axesLabels=c("", ""), legend=TRUE)
    title(main="LLE")
    
    dev.off()
    
    # ==========================================
    # 6. Save Outputs
    # ==========================================
    
    # Save coordinates as CSV files
    write.csv(golubIsomap\$dim2, "isomap_coordinates.csv", row.names = TRUE)
    write.csv(golubLLE, "lle_coordinates.csv", row.names = TRUE)
    
    # Save full objects as RDS
    saveRDS(golubIsomap, "golubIsomap.rds")
    saveRDS(golubLLE, "golubLLE.rds")

    writeLines(c(
        '"BIOC_RDRTOOLBOX_NONLINEAR_DIMENSION_REDUCTION":',
        paste0('    RDRToolbox: ', as.character(packageVersion('RDRToolbox')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_nonlinear_dimension_reduction.csv versions.yml
    """
}

workflow BIOC_RDRTOOLBOX_NONLINEAR_DIMENSION_REDUCTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv, sample_metadata.csv ] ]

    main:
    BIOC_RDRTOOLBOX_NONLINEAR_DIMENSION_REDUCTION(ch_input)

    emit:
    tables   = BIOC_RDRTOOLBOX_NONLINEAR_DIMENSION_REDUCTION.out.tables
    plots    = BIOC_RDRTOOLBOX_NONLINEAR_DIMENSION_REDUCTION.out.plots
    objects  = BIOC_RDRTOOLBOX_NONLINEAR_DIMENSION_REDUCTION.out.objects
    versions = BIOC_RDRTOOLBOX_NONLINEAR_DIMENSION_REDUCTION.out.versions
}
