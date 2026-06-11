#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: blima — alternative_preprocessing_options
// Apply alternative background subtraction, RMA-like convolution, or log2 transformation methods on bead-level data.
// Input: blimatestingall, negAdr
// Container: quay.io/biocontainers/bioconductor-blima:1.40.0--r44he5774e6_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: beadarray, blima
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Perform graphical background subtraction or RMA-like background convolution. 2. Apply log2 transformation instead of variance stab

nextflow.enable.dsl = 2

process BIOC_BLIMA_ALTERNATIVE_PREPROCESSING_OPTIONS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    library(blima)
    library(beadarray)
    
    # 1. Read user input files from the working directory
    if (!file.exists("blimatestingall.rds") || !file.exists("negAdr.rds")) {
      stop("Required input files 'blimatestingall.rds' and/or 'negAdr.rds' are missing from the working directory.")
    }
    
    blimatestingall <- readRDS("blimatestingall.rds")
    negAdr <- readRDS("negAdr.rds")
    
    # Ensure the background filter channel "bgf" exists, as it is required by xieBacgroundCorrect.
    # If it does not exist, we generate it using bacgroundCorrect.
    tryCatch({
      # Check if "bgf" is present in the first array of the first object
      if (length(blimatestingall) > 0) {
        first_obj <- blimatestingall[[1]]
        # Check if "bgf" channel exists by attempting to retrieve it
        has_bgf <- tryCatch({
          invisible(beadarray::getBeadData(first_obj, array = 1, what = "bgf"))
          TRUE
        }, error = function(e) FALSE)
        
        if (!has_bgf) {
          message("Creating 'bgf' channel using bacgroundCorrect...")
          blimatestingall <- bacgroundCorrect(blimatestingall, channelBackground = "GrnB",
                                              channelBackgroundFilter = "bgf")
        }
      }
    }, error = function(e) {
      warning("Failed to check/create 'bgf' channel: ", e\$message)
    })
    
    # 2. Perform graphical background subtraction
    message("Performing background channel subtraction...")
    blimatestingall = backgroundChannelSubtract(blimatestingall, normalizationMod = NULL,
            channelSubtractFrom = "GrnF", channelSubtractWhat = "GrnB", channelResult = "BGS")
    
    # 3. Perform RMA-like background convolution (Xie background correction)
    message("Performing Xie background correction...")
    blimatestingall = xieBacgroundCorrect(blimatestingall, normalizationMod = NULL,
            negativeArrayAddresses=negAdr, channelCorrect="GrnF", channelResult="XIE",
            channelInclude="bgf")
    
    # 4. Apply log2 transformation instead of variance stabilization
    message("Applying log2 transformation...")
    blimatestingall = selectedChannelTransform(blimatestingall, normalizationMod=NULL,
            channelTransformFrom="GrnF", channelResult="LOG",
            transformation=log2TransformPositive)
    
    # 5. Save the processed beadLevelData object
    message("Saving processed beadLevelData object...")
    saveRDS(blimatestingall, "processed_blimatestingall.rds")
    
    # 6. Generate summary statistics and output CSV
    message("Generating channel summary statistics...")
    summary_list <- list()
    if (length(blimatestingall) > 0) {
      data1 <- blimatestingall[[1]]
      channels <- c("GrnF", "BGS", "XIE", "LOG")
      for (ch in channels) {
        tryCatch({
          vals <- beadarray::getBeadData(data1, array = 1, what = ch)
          summary_list[[ch]] <- data.frame(
            Channel = ch,
            Mean = mean(vals, na.rm = TRUE),
            SD = sd(vals, na.rm = TRUE),
            Min = min(vals, na.rm = TRUE),
            Max = max(vals, na.rm = TRUE)
          )
        }, error = function(e) {
          warning("Could not calculate statistics for channel ", ch, ": ", e\$message)
        })
      }
    }
    
    if (length(summary_list) > 0) {
      summary_df <- do.call(rbind, summary_list)
      write.csv(summary_df, "channel_summaries.csv", row.names = FALSE)
      message("Saved channel summaries to 'channel_summaries.csv'.")
    }
    
    # 7. Generate diagnostic plots
    message("Generating diagnostic plots...")
    pdf("preprocessing_comparison.pdf", width = 10, height = 8)
    par(mfrow = c(2, 2))
    if (length(blimatestingall) > 0) {
      data1 <- blimatestingall[[1]]
      channels <- c("GrnF", "BGS", "XIE", "LOG")
      for (ch in channels) {
        tryCatch({
          vals <- beadarray::getBeadData(data1, array = 1, what = ch)
          plot(density(vals, na.rm = TRUE), main = paste("Density of", ch), xlab = "Intensity", col = "blue", lwd = 2)
        }, error = function(e) {
          plot(1, type = "n", main = paste("Density of", ch), xlab = "", ylab = "")
          text(1, 1, paste("Error:", e\$message), col = "red")
        })
      }
    }
    dev.off()
    message("Saved diagnostic plots to 'preprocessing_comparison.pdf'.")
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_BLIMA_ALTERNATIVE_PREPROCESSING_OPTIONS":',
        paste0('    blima: ', as.character(packageVersion('blima')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_alternative_preprocessing_options.csv versions.yml
    """
}

workflow BIOC_BLIMA_ALTERNATIVE_PREPROCESSING_OPTIONS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ blimatestingall, negAdr ] ]

    main:
    BIOC_BLIMA_ALTERNATIVE_PREPROCESSING_OPTIONS(ch_input)

    emit:
    tables   = BIOC_BLIMA_ALTERNATIVE_PREPROCESSING_OPTIONS.out.tables
    plots    = BIOC_BLIMA_ALTERNATIVE_PREPROCESSING_OPTIONS.out.plots
    objects  = BIOC_BLIMA_ALTERNATIVE_PREPROCESSING_OPTIONS.out.objects
    versions = BIOC_BLIMA_ALTERNATIVE_PREPROCESSING_OPTIONS.out.versions
}
