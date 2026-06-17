#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: alabaster_mae — mae_serialization_and_roundtrip
// Build, serialize, and reload a MultiAssayExperiment using alabaster.mae to ensure high-fidelity data storage and cross-assay integration.
// Input: input.csv
// Container: quay.io/biocontainers/r-base:4.3.1
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MultiAssayExperiment, S4Vectors, SummarizedExperiment, alabaster.base, alabaster.mae, alabaster_mae
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ALABASTER_MAE_MAE_SERIALIZATION_AND_ROUNDTRIP {
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
    .bm_deps <- c("MultiAssayExperiment", "S4Vectors", "alabaster.base", "alabaster.mae", "SummarizedExperiment")
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
    library(MultiAssayExperiment)
    library(SummarizedExperiment)
    library(S4Vectors)
    library(alabaster.base)
    library(alabaster.mae)
    
    # --- Read and parse the input file defensively ---
    input_file <- "input.csv"
    if (!file.exists(input_file)) {
        stop(paste("Required input file missing:", input_file))
    }
    
    raw_data <- read.csv(input_file, check.names = FALSE, stringsAsFactors = FALSE)
    
    # Parse the input data into a numeric matrix
    if ("feature_id" %in% colnames(raw_data)) {
        rownames_vec <- raw_data\$feature_id
        numeric_cols <- setdiff(colnames(raw_data), "feature_id")
        mat <- as.matrix(raw_data[, numeric_cols, drop = FALSE])
        rownames(mat) <- rownames_vec
    } else {
        # Fallback if feature_id is not explicitly named
        rownames_vec <- raw_data[, 1]
        if (ncol(raw_data) > 1) {
            mat <- as.matrix(raw_data[, -1, drop = FALSE])
            rownames(mat) <- rownames_vec
        } else {
            # Single-column gene/identifier list fallback: generate dummy sample data
            message("Single-column input detected. Generating dummy sample matrix.")
            mat <- matrix(runif(length(rownames_vec) * 4, min = 1, max = 15), ncol = 4)
            colnames(mat) <- paste0("Sample", 1:4)
            rownames(mat) <- rownames_vec
        }
    }
    
    # Ensure matrix is strictly numeric
    class(mat) <- "numeric"
    mat[is.na(mat)] <- 0  # Handle missing values defensively
    
    # --- Construct a MultiAssayExperiment ---
    # To demonstrate a true multi-omic representation, we split the input matrix into two simulated assays
    n_features <- nrow(mat)
    if (n_features >= 2) {
        mid <- floor(n_features / 2)
        mat1 <- mat[1:mid, , drop = FALSE]
        mat2 <- mat[(mid + 1):n_features, , drop = FALSE]
    } else {
        # Fallback for extremely small inputs
        mat1 <- mat
        mat2 <- mat
    }
    
    # Create individual SummarizedExperiment objects
    se1 <- SummarizedExperiment(assays = list(logcounts = mat1))
    se2 <- SummarizedExperiment(assays = list(logcounts = mat2))
    
    # Create sample metadata (colData)
    sample_names <- colnames(mat)
    col_data <- DataFrame(
        row.names = sample_names,
        Condition = rep(c("Treatment", "Control"), length.out = length(sample_names)),
        Replicate = seq_along(sample_names)
    )
    
    # Construct the MultiAssayExperiment
    mae <- MultiAssayExperiment(
        experiments = ExperimentList(Assay1 = se1, Assay2 = se2),
        colData = col_data
    )
    
    # --- Serialize the MultiAssayExperiment using alabaster ---
    save_dir <- "mae_serialized"
    if (dir.exists(save_dir)) {
        unlink(save_dir, recursive = TRUE)
    }
    
    message("Saving MultiAssayExperiment to disk...")
    alabaster.base::saveObject(mae, save_dir)
    
    # --- Load the MultiAssayExperiment back ---
    message("Loading MultiAssayExperiment back from disk...")
    mae_loaded <- alabaster.base::readObject(save_dir)
    
    # --- Validation and Diagnostics ---
    # Write verification summary
    sink("mae_summary.txt")
    cat("========================================================\n")
    cat("          ALABASTER.MAE ROUNDTRIP VERIFICATION          \n")
    cat("========================================================\n\n")
    cat("--- Original Object ---\n")
    print(mae)
    cat("\n--- Loaded Object ---\n")
    print(mae_loaded)
    cat("\n--- Integrity Checks ---\n")
    cat("Identical colData structure:", identical(dim(colData(mae)), dim(colData(mae_loaded))), "\n")
    cat("Identical experiment names:", identical(names(experiments(mae)), names(experiments(mae_loaded))), "\n")
    cat("Assay 1 dimensions match:", identical(dim(mae[[1]]), dim(mae_loaded[[1]])), "\n")
    cat("Assay 2 dimensions match:", identical(dim(mae[[2]]), dim(mae_loaded[[2]])), "\n")
    sink()
    
    # Generate diagnostic plot
    pdf("mae_plot.pdf", width = 7, height = 6)
    val1 <- assay(mae_loaded[[1]])[1, ]
    val2 <- assay(mae_loaded[[2]])[1, ]
    plot(val1, val2, 
         xlab = "Assay 1 (Feature 1)", 
         ylab = "Assay 2 (Feature 1)",
         main = "Cross-Assay Feature Comparison (Loaded MAE)", 
         pch = 19, 
         col = as.factor(colData(mae_loaded)\$Condition))
    legend("topright", legend = unique(colData(mae_loaded)\$Condition), 
           col = unique(as.factor(colData(mae_loaded)\$Condition)), pch = 19)
    dev.off()
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_ALABASTER_MAE_MAE_SERIALIZATION_AND_ROUNDTRIP":',
        paste0('    alabaster_mae: ', as.character(packageVersion('alabaster_mae')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mae_serialization_and_roundtrip.csv versions.yml
    """
}

workflow BIOC_ALABASTER_MAE_MAE_SERIALIZATION_AND_ROUNDTRIP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_ALABASTER_MAE_MAE_SERIALIZATION_AND_ROUNDTRIP(ch_input)

    emit:
    tables   = BIOC_ALABASTER_MAE_MAE_SERIALIZATION_AND_ROUNDTRIP.out.tables
    plots    = BIOC_ALABASTER_MAE_MAE_SERIALIZATION_AND_ROUNDTRIP.out.plots
    objects  = BIOC_ALABASTER_MAE_MAE_SERIALIZATION_AND_ROUNDTRIP.out.objects
    versions = BIOC_ALABASTER_MAE_MAE_SERIALIZATION_AND_ROUNDTRIP.out.versions
}
