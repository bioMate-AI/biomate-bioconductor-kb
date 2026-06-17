#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: alabaster_base — alabaster_object_serialization
// Serialize and deserialize Bioconductor S4 DataFrames containing feature data and metadata using the alabaster framework to ensure standardized, reproducible on-
// Input: input.csv
// Container: quay.io/biocontainers/r-base:4.3.1
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: S4Vectors, alabaster.base, alabaster_base
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ALABASTER_BASE_ALABASTER_OBJECT_SERIALIZATION {
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
    .bm_deps <- c("S4Vectors", "alabaster.base")
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
    library(S4Vectors)
    library(alabaster.base)
    
    # ==========================================
    # --- Defensive Input Reading & Parsing ---
    # ==========================================
    
    input_file <- "input.csv"
    if (!file.exists(input_file)) {
        stop(paste("Required input file missing:", input_file))
    }
    
    # Read the input CSV defensively
    raw_data <- read.csv(input_file, header = TRUE, check.names = FALSE, stringsAsFactors = FALSE)
    
    if (nrow(raw_data) == 0) {
        stop("Input dataset is empty.")
    }
    
    # Determine if the input is a single-column gene list or a feature-by-sample matrix
    is_gene_list <- FALSE
    feature_ids <- NULL
    matrix_data <- NULL
    
    if (ncol(raw_data) == 1) {
        is_gene_list <- TRUE
        feature_ids <- raw_data[[1]]
    } else {
        # Check for 'feature_id' column
        if ("feature_id" %in% colnames(raw_data)) {
            feature_ids <- raw_data\$feature_id
            # Drop the feature_id column to isolate numeric data
            numeric_df <- raw_data[, setdiff(colnames(raw_data), "feature_id"), drop = FALSE]
        } else {
            # Assume first column is the identifier if it is non-numeric
            if (!is.numeric(raw_data[[1]])) {
                feature_ids <- raw_data[[1]]
                numeric_df <- raw_data[, -1, drop = FALSE]
            } else {
                feature_ids <- paste0("Feature_", seq_len(nrow(raw_data)))
                numeric_df <- raw_data
            }
        }
        
        # Verify if the remaining columns are numeric
        is_numeric_cols <- sapply(numeric_df, is.numeric)
        if (any(is_numeric_cols)) {
            matrix_data <- as.matrix(numeric_df[, is_numeric_cols, drop = FALSE])
            rownames(matrix_data) <- feature_ids
        } else {
            is_gene_list <- TRUE
        }
    }
    
    # ==========================================
    # --- Construct the S4 DataFrame Object ---
    # ==========================================
    
    message("Constructing S4 DataFrame object...")
    if (is_gene_list) {
        # Construct a simple S4 DataFrame for gene list
        df_s4 <- DataFrame(
            FeatureID = feature_ids,
            row.names = feature_ids
        )
        # Add custom metadata
        metadata(df_s4) <- list(
            dataType = "GeneList",
            created = as.character(Sys.time()),
            total_features = length(feature_ids)
        )
    } else {
        # Compute basic row-wise statistics
        row_means <- rowMeans(matrix_data, na.rm = TRUE)
        row_sds <- apply(matrix_data, 1, sd, na.rm = TRUE)
        # Replace NA SDs (e.g., single sample) with 0
        row_sds[is.na(row_sds)] <- 0
        
        # Construct a rich S4 DataFrame
        df_s4 <- DataFrame(
            matrix_data,
            RowMean = row_means,
            RowSD = row_sds,
            row.names = feature_ids
        )
        # Add custom metadata
        metadata(df_s4) <- list(
            dataType = "NumericMatrix",
            created = as.character(Sys.time()),
            total_features = nrow(matrix_data),
            num_samples = ncol(matrix_data)
        )
    }
    
    # ==========================================
    # --- Serialize Object using Alabaster ---
    # ==========================================
    
    save_dir <- "alabaster_data_store"
    if (dir.exists(save_dir)) {
        unlink(save_dir, recursive = TRUE)
    }
    
    message("Saving S4 object to disk using alabaster.base...")
    # Save the S4 DataFrame to the specified directory
    alabaster.base::saveObject(df_s4, save_dir)
    
    # ==========================================
    # --- Deserialize and Validate Object ---
    # ==========================================
    
    message("Reading S4 object back from disk...")
    # Load the object back using alabaster's readObject
    loaded_df <- alabaster.base::readObject(save_dir)
    
    # Validate integrity of the loaded object
    validation_success <- TRUE
    if (!identical(dim(df_s4), dim(loaded_df))) {
        warning("Dimension mismatch between original and loaded object!")
        validation_success <- FALSE
    }
    
    if (!identical(metadata(df_s4)\$dataType, metadata(loaded_df)\$dataType)) {
        warning("Metadata mismatch between original and loaded object!")
        validation_success <- FALSE
    }
    
    # ==========================================
    # --- Downstream Analysis & Outputs ---
    # ==========================================
    
    message("Generating final outputs...")
    
    # Convert loaded S4 DataFrame to a standard data.frame for export
    export_df <- as.data.frame(loaded_df)
    export_df\$ValidationStatus <- ifelse(validation_success, "PASSED", "FAILED")
    
    # Write the summary CSV
    write.csv(export_df, "analysis_summary.csv", row.names = TRUE)
    
    # Generate diagnostic plots
    pdf("feature_properties.pdf", width = 8, height = 6)
    if (metadata(loaded_df)\$dataType == "NumericMatrix") {
        # Plot Row Mean vs Row SD
        plot(
            loaded_df\$RowMean, 
            loaded_df\$RowSD, 
            pch = 16, 
            col = "steelblue",
            xlab = "Feature Mean", 
            ylab = "Feature Standard Deviation",
            main = "Feature Properties (Deserialized Alabaster Object)"
        )
        abline(h = mean(loaded_df\$RowSD), col = "red", lty = 2)
        legend("topright", legend = "Mean SD", col = "red", lty = 2)
    } else {
        # Plot a simple bar chart of character lengths for gene list
        char_lengths <- nchar(as.character(loaded_df\$FeatureID))
        hist(
            char_lengths, 
            col = "darkseagreen", 
            xlab = "Character Length of Identifiers",
            main = "Identifier Length Distribution (Deserialized Alabaster Object)"
        )
    }
    dev.off()
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_ALABASTER_BASE_ALABASTER_OBJECT_SERIALIZATION":',
        paste0('    alabaster_base: ', as.character(packageVersion('alabaster_base')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_alabaster_object_serialization.csv versions.yml
    """
}

workflow BIOC_ALABASTER_BASE_ALABASTER_OBJECT_SERIALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_ALABASTER_BASE_ALABASTER_OBJECT_SERIALIZATION(ch_input)

    emit:
    tables   = BIOC_ALABASTER_BASE_ALABASTER_OBJECT_SERIALIZATION.out.tables
    plots    = BIOC_ALABASTER_BASE_ALABASTER_OBJECT_SERIALIZATION.out.plots
    objects  = BIOC_ALABASTER_BASE_ALABASTER_OBJECT_SERIALIZATION.out.objects
    versions = BIOC_ALABASTER_BASE_ALABASTER_OBJECT_SERIALIZATION.out.versions
}
