#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: vsn — rglist_normalization
// Normalize and transform two-color microarray data stored in an RGList object.
// Input: lymRG, lymRGwbg
// Container: quay.io/biocontainers/bioconductor-vsn:3.78.1--r45h01b2380_0
// R packages: Biobase, limma, vsn
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, limma, vsn
// Visualizations: mean-SD plot
// QC: variance-stabilizing normalization, normalization diagnostic plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run justvsn on the RGList object
//  * 2. [Core Analysis] Run justvsn with background subtraction on a subset of
//  * 3. [Core Analysis] Run justvsn with print-tip strata on the first array

nextflow.enable.dsl = 2

process BIOC_VSN_RGLIST_NORMALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20"

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
    .bm_deps <- c("Biobase", "limma", "vsn")
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
            library(vsn)
            library(limma)
            library(Biobase)
            
            # Read the user input files from the working directory
            # The pipeline expects 'lymRG.rds' and 'lymRGwbg.rds' to exist in the working directory.
            lymRG <- readRDS("lymRG.rds")
            lymRGwbg <- readRDS("lymRGwbg.rds")
            
            # Reconstruct array geometry for print-tip groups (strata) as described in the documentation
            # Adapted to avoid hardcoded dimensions and work with arbitrary RGList inputs
            ngr <- ngc <- 4L
            n_features <- nrow(lymRG)
            arrayGeometry <- data.frame(
              pin = rep(1:(ngr * ngc), length.out = n_features)
            )
            
            # --- Run justvsn on the RGList object ---
            lymNCS = justvsn(lymRG)
            
            # --- Run justvsn with background subtraction on a subset of ---
            num_arrays <- min(3, ncol(lymRGwbg))
            lymESwbg = justvsn(lymRGwbg[, 1:num_arrays], backgroundsubtract=TRUE)
            
            # --- Run justvsn with print-tip strata on the first array ---
            EconStr = justvsn(lymRG[, 1], strata = arrayGeometry\$pin)
            
            # Save the processed NChannelSet objects to RDS files
            saveRDS(lymNCS, file = "lymNCS.rds")
            saveRDS(lymESwbg, file = "lymESwbg.rds")
            saveRDS(EconStr, file = "EconStr.rds")
            
            # Generate diagnostic plots to assess variance stabilization
            pdf("vsn_diagnostics.pdf", width = 10, height = 5)
            # Plot standard deviation versus rank of the mean for the fully normalized dataset
            print(meanSdPlot(lymNCS))
            dev.off()
            
            # Export a summary of the normalized intensities (e.g., first 100 rows) to a CSV file
            num_features_summary <- min(100, nrow(lymNCS))
            normalized_R <- assayData(lymNCS)\$R[1:num_features_summary, , drop = FALSE]
            normalized_G <- assayData(lymNCS)\$G[1:num_features_summary, , drop = FALSE]
            
            feature_names <- rownames(normalized_R)
            if (is.null(feature_names)) {
              feature_names <- 1:num_features_summary
            }
            
            summary_df <- data.frame(
              Feature = feature_names,
              R_Array1 = normalized_R[, 1],
              G_Array1 = normalized_G[, 1]
            )
            write.csv(summary_df, file = "normalized_intensities_summary.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_VSN_RGLIST_NORMALIZATION":',
        paste0('    vsn: ', as.character(packageVersion('vsn')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rglist_normalization.csv versions.yml
    """
}

workflow BIOC_VSN_RGLIST_NORMALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ lymRG, lymRGwbg ] ]

    main:
    BIOC_VSN_RGLIST_NORMALIZATION(ch_input)

    emit:
    tables   = BIOC_VSN_RGLIST_NORMALIZATION.out.tables
    plots    = BIOC_VSN_RGLIST_NORMALIZATION.out.plots
    objects  = BIOC_VSN_RGLIST_NORMALIZATION.out.objects
    versions = BIOC_VSN_RGLIST_NORMALIZATION.out.versions
}
