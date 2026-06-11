#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rpx — rpx_proteomexchange_pipeline
// Query ProteomeXchange metadata and download associated files dynamically using rpx, integrating with local user-provided intensity data.
// Input: intensity.csv, coldata.csv
// Container: 2.18.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, rpx
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RPX_RPX_PROTEOMEXCHANGE_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20"

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
    
    library(rpx)
    
    # --- Load and process user input files ---
    message("Loading user input files...")
    intensity_df <- read.csv("intensity.csv", check.names = FALSE)
    coldata_df <- read.csv("coldata.csv", check.names = FALSE)
    
    # Set row names for intensity
    if ("feature_id" %in% colnames(intensity_df)) {
      rownames(intensity_df) <- intensity_df\$feature_id
      intensity_matrix <- as.matrix(intensity_df[, setdiff(colnames(intensity_df), "feature_id"), drop = FALSE])
    } else {
      rownames(intensity_df) <- intensity_df[, 1]
      intensity_matrix <- as.matrix(intensity_df[, -1, drop = FALSE])
    }
    
    # Set row names for coldata
    rownames(coldata_df) <- coldata_df\$sample
    
    # Align samples
    common_samples <- intersect(colnames(intensity_matrix), rownames(coldata_df))
    if (length(common_samples) == 0) {
      stop("No common samples found between intensity.csv and coldata.csv")
    }
    intensity_matrix <- intensity_matrix[, common_samples, drop = FALSE]
    coldata_df <- coldata_df[common_samples, , drop = FALSE]
    
    # Construct SummarizedExperiment
    se <- SummarizedExperiment(
      assays = list(counts = intensity_matrix),
      colData = DataFrame(coldata_df)
    )
    
    # --- Query ProteomeXchange dynamically ---
    message("Querying ProteomeXchange...")
    px_id <- NULL
    
    # Try to get announced projects
    tryCatch({
      ann <- pxannounced()
      if (!is.null(ann) && nrow(ann) > 0) {
        px_ids <- ann\$id
        px_id <- px_ids[grep("^PXD", px_ids)][1]
      }
    }, error = function(e) {
      message("Failed to fetch announced projects: ", e\$message)
    })
    
    # Try cached projects if announced failed
    if (is.null(px_id) || is.na(px_id)) {
      tryCatch({
        cached <- pxCachedProjects()
        if (!is.null(cached) && nrow(cached) > 0) {
          px_id <- cached\$pxid[1]
        }
      }, error = function(e) {
        message("Failed to fetch cached projects: ", e\$message)
      })
    }
    
    # Fallback to a standard ID if both queries failed
    if (is.null(px_id) || is.na(px_id)) {
      px_id <- "PXD000001"
    }
    
    message("Selected ProteomeXchange ID: ", px_id)
    
    # --- Retrieve PX Dataset and Metadata ---
    px_metadata <- data.frame(
      pxid = px_id,
      title = "Unknown",
      tax = "Unknown",
      url = "Unknown",
      ref = "Unknown",
      submission_date = "Unknown",
      publication_date = "Unknown",
      instruments = "Unknown",
      protocols = "Unknown",
      ptms = "Unknown"
    )
    
    px_files <- "No files retrieved"
    
    tryCatch({
      px <- PXDataset(px_id)
    
      # Extract metadata safely
      px_metadata <- data.frame(
        pxid = ifelse(!is.null(pxid(px)), pxid(px), px_id),
        title = ifelse(!is.null(pxtitle(px)), pxtitle(px), "Unknown"),
        tax = paste(pxtax(px), collapse = "; "),
        url = ifelse(!is.null(pxurl(px)), pxurl(px), "Unknown"),
        ref = paste(pxref(px), collapse = "; "),
        submission_date = as.character(pxSubmissionDate(px)),
        publication_date = as.character(pxPublicationDate(px)),
        instruments = paste(pxinstruments(px), collapse = "; "),
        protocols = paste(pxprotocols(px), collapse = "; "),
        ptms = paste(pxptms(px), collapse = "; ")
      )
    
      px_files <- pxfiles(px)
    }, error = function(e) {
      message("Error retrieving PX dataset metadata: ", e\$message)
    })
    
    # Write metadata and file list
    write.csv(px_metadata, "px_metadata.csv", row.names = FALSE)
    
    if (is.character(px_files) && length(px_files) > 0) {
      write.csv(data.frame(file_name = px_files), "px_files_list.csv", row.names = FALSE)
    } else {
      write.csv(data.frame(file_name = "No files found"), "px_files_list.csv", row.names = FALSE)
    }
    
    # --- Download a small file from the dataset ---
    downloaded_file_path <- NULL
    if (exists("px") && !is.null(px_files) && length(px_files) > 0 && !identical(px_files, "No files retrieved")) {
      # Look for a small text/readme file
      readme_idx <- grep("README|readme|txt", px_files, ignore.case = TRUE)
      target_file <- if (length(readme_idx) > 0) px_files[readme_idx[1]] else px_files[1]
    
      message("Attempting to download file: ", target_file)
      tryCatch({
        downloaded_file_path <- pxget(px, target_file)
      }, error = function(e) {
        message("Failed to download file: ", e\$message)
      })
    }
    
    if (!is.null(downloaded_file_path) && file.exists(downloaded_file_path)) {
      file.copy(downloaded_file_path, "downloaded_px_file.txt", overwrite = TRUE)
      message("Successfully downloaded and saved file to downloaded_px_file.txt")
    } else {
      writeLines("No file downloaded or download failed.", "downloaded_px_file.txt")
    }
    
    # --- Analyze user intensity data and export summary ---
    message("Analyzing user intensity data...")
    conditions <- unique(colData(se)\$condition)
    mean_intensities <- sapply(conditions, function(cond) {
      samples <- rownames(colData(se))[colData(se)\$condition == cond]
      rowMeans(assay(se, "counts")[, samples, drop = FALSE], na.rm = TRUE)
    })
    colnames(mean_intensities) <- paste0("mean_", conditions)
    
    user_summary <- data.frame(
      feature_id = rownames(se),
      mean_intensities,
      check.names = FALSE
    )
    write.csv(user_summary, "user_intensity_summary.csv", row.names = FALSE)
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_RPX_RPX_PROTEOMEXCHANGE_PIPELINE":',
        paste0('    rpx: ', as.character(packageVersion('rpx')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rpx_proteomexchange_pipeline.csv versions.yml
    """
}

workflow BIOC_RPX_RPX_PROTEOMEXCHANGE_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_RPX_RPX_PROTEOMEXCHANGE_PIPELINE(ch_input)

    emit:
    tables   = BIOC_RPX_RPX_PROTEOMEXCHANGE_PIPELINE.out.tables
    plots    = BIOC_RPX_RPX_PROTEOMEXCHANGE_PIPELINE.out.plots
    objects  = BIOC_RPX_RPX_PROTEOMEXCHANGE_PIPELINE.out.objects
    versions = BIOC_RPX_RPX_PROTEOMEXCHANGE_PIPELINE.out.versions
}
