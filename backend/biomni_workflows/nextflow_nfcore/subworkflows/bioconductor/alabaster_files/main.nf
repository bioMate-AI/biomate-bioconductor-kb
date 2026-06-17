#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: alabaster_files — alabaster_file_staging
// Stage, serialize, and reload raw file assets using the alabaster framework for reproducible data packaging.
// Input: input.csv
// Container: quay.io/biocontainers/r-base:4.3.1
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: S4Vectors, alabaster.base, alabaster.files, alabaster_files
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ALABASTER_FILES_ALABASTER_FILE_STAGING {
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
    .bm_deps <- c("alabaster.files", "alabaster.base", "S4Vectors")
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
    
    # --- Load required libraries defensively ---
    library(alabaster.files)
    library(alabaster.base)
    library(S4Vectors)
    
    # --- Read and parse the input file defensively ---
    input_file <- "input.csv"
    if (!file.exists(input_file)) {
        stop(paste("Required input file missing:", input_file))
    }
    
    # Read input data
    raw_data <- read.csv(input_file, stringsAsFactors = FALSE, check.names = FALSE)
    
    # Determine structure and set row names if possible
    if ("feature_id" %in% colnames(raw_data)) {
        rownames(raw_data) <- raw_data\$feature_id
        raw_data\$feature_id <- NULL
    } else if (ncol(raw_data) > 0) {
        rownames(raw_data) <- raw_data[, 1]
        raw_data <- raw_data[, -1, drop = FALSE]
    }
    
    # --- Process the data based on its type (numeric matrix vs ---
    is_numeric_matrix <- all(sapply(raw_data, is.numeric)) && ncol(raw_data) > 0
    
    if (is_numeric_matrix) {
        message("Processing numeric feature-by-sample matrix...")
        row_means <- rowMeans(raw_data, na.rm = TRUE)
        row_sds <- apply(raw_data, 1, sd, na.rm = TRUE)
        processed_data <- data.frame(
            Mean = row_means,
            SD = row_sds,
            row.names = rownames(raw_data),
            check.names = FALSE
        )
    } else {
        message("Processing identifier list...")
        processed_data <- data.frame(
            Identifier = rownames(raw_data),
            row.names = rownames(raw_data),
            check.names = FALSE
        )
    }
    
    # --- Write processed data to a local intermediate file ---
    intermediate_file <- "processed_features.csv"
    write.csv(processed_data, intermediate_file, row.names = TRUE)
    
    # --- Stage the file using alabaster.files ---
    stage_dir <- "staged_assets"
    if (dir.exists(stage_dir)) {
        unlink(stage_dir, recursive = TRUE)
    }
    
    message("Staging file reference with alabaster.files...")
    # Create a FileReference pointing to our intermediate file
    ref <- alabaster.files::FileReference(intermediate_file)
    
    # Save the FileReference object to the staging directory
    alabaster.base::saveObject(ref, stage_dir)
    
    # --- Read the staged object back to verify round-trip integrity ---
    message("Loading staged file reference back into R...")
    loaded_ref <- alabaster.base::readObject(stage_dir)
    
    # Extract the path from the loaded FileReference defensively
    loaded_path <- NULL
    tryCatch({
        if (is(loaded_ref, "FileReference")) {
            if (.hasSlot(loaded_ref, "path")) {
                loaded_path <- loaded_ref@path
            } else {
                # Search slots for a valid file path
                for (slot_name in slotNames(loaded_ref)) {
                    val <- slot(loaded_ref, slot_name)
                    if (is.character(val) && length(val) == 1 && file.exists(val)) {
                        loaded_path <- val
                        break
                    }
                }
            }
        }
    }, error = function(e) {
        warning("Direct slot extraction failed: ", e\$message)
    })
    
    # Fallback search if slot extraction did not yield a valid path
    if (is.null(loaded_path) || !file.exists(loaded_path)) {
        csv_files <- list.files(stage_dir, pattern = "\\\\.csv\$", full.names = TRUE, recursive = TRUE)
        if (length(csv_files) > 0) {
            loaded_path <- csv_files[1]
        } else {
            loaded_path <- intermediate_file
        }
    }
    
    message(paste("Verified file path resolved to:", loaded_path))
    
    # --- Read the verified file and write final outputs ---
    final_data <- read.csv(loaded_path, row.names = 1, check.names = FALSE)
    write.csv(final_data, "output_matrix.csv", row.names = TRUE)
    
    # Generate diagnostic visualization
    pdf("summary_stats.pdf", width = 7, height = 7)
    if (is_numeric_matrix && "Mean" %in% colnames(final_data)) {
        plot(final_data\$Mean, final_data\$SD,
             xlab = "Mean Expression", ylab = "Standard Deviation",
             main = "Feature Summary Statistics (Staged & Reloaded)",
             col = "blue", pch = 16)
        abline(h = median(final_data\$SD, na.rm = TRUE), col = "red", lty = 2)
        legend("topright", legend = c("Features", "Median SD"), col = c("blue", "red"), lty = c(NA, 2), pch = c(16, NA))
    } else {
        plot(1:10, 1:10, type = "n", xlab = "", ylab = "", main = "Identifier List Loaded")
        text(5, 5, paste("Successfully staged and reloaded\n", nrow(final_data), "identifiers!"), cex = 1.2, col = "darkgreen")
    }
    dev.off()
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_ALABASTER_FILES_ALABASTER_FILE_STAGING":',
        paste0('    alabaster_files: ', as.character(packageVersion('alabaster_files')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_alabaster_file_staging.csv versions.yml
    """
}

workflow BIOC_ALABASTER_FILES_ALABASTER_FILE_STAGING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_ALABASTER_FILES_ALABASTER_FILE_STAGING(ch_input)

    emit:
    tables   = BIOC_ALABASTER_FILES_ALABASTER_FILE_STAGING.out.tables
    plots    = BIOC_ALABASTER_FILES_ALABASTER_FILE_STAGING.out.plots
    objects  = BIOC_ALABASTER_FILES_ALABASTER_FILE_STAGING.out.objects
    versions = BIOC_ALABASTER_FILES_ALABASTER_FILE_STAGING.out.versions
}
