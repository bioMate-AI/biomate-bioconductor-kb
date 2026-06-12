#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: epialleler — methylation_bimodality_ecdf
// Visualize per-read beta value distributions and empirical cumulative distribution functions (eCDFs) to assess bimodality.
// Input: amplicon010meth.bam, amplicon.bed
// Container: quay.io/biocontainers/bioconductor-epialleler:1.18.0--r45ha27e39d_0
// R packages: epialleleR
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EPIALLELER_METHYLATION_BIMODALITY_ECDF {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-epialleler:1.18.0--r45ha27e39d_0"

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
    .bm_deps <- c("epialleleR")
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
    library(epialleleR)
    
    # Define input files exactly as specified
    bam_file <- "amplicon010meth.bam"
    bed_file <- "amplicon.bed"
    
    # Verify input files exist
    if (!file.exists(bam_file)) {
      stop(paste("Required BAM file missing:", bam_file))
    }
    if (!file.exists(bed_file)) {
      stop(paste("Required BED file missing:", bed_file))
    }
    
    # ------------------------------------------------------------------------------
    # --- Compute eCDFs for within- and out-of-context per-read ---
    # ------------------------------------------------------------------------------
    message("Computing eCDFs using generateBedEcdf...")
    amplicon.ecdfs <- generateBedEcdf(
      bam = bam_file,
      bed = bed_file,
      bed.rows = NULL
    )
    
    # Save the raw eCDF list object as an RDS file
    saveRDS(amplicon.ecdfs, file = "amplicon_ecdfs.rds")
    message("Saved eCDF list object to 'amplicon_ecdfs.rds'")
    
    # ------------------------------------------------------------------------------
    # --- Plot the eCDFs for context and out-of-context ---
    # ------------------------------------------------------------------------------
    message("Generating eCDF plots...")
    pdf("amplicon_ecdfs_plot.pdf", width = 3 * length(amplicon.ecdfs), height = 4)
    
    # Set up plotting grid
    par(mfrow = c(1, length(amplicon.ecdfs)))
    
    # Cycle through items and plot
    for (x in 1:length(amplicon.ecdfs)) {
      main <- if (is.na(names(amplicon.ecdfs[x]))) "unmatched" else names(amplicon.ecdfs[x])
      
      # Plotting eCDF for within-the-context per-read beta values (in red)
      plot(
        amplicon.ecdfs[[x]]\$context,
        col = "red",
        verticals = TRUE,
        do.points = FALSE,
        xlim = c(0, 1),
        xlab = "per-read beta value",
        ylab = "cumulative density",
        main = main
      )
      
      # Adding eCDF for out-of-context per-read beta values (in blue)
      plot(
        amplicon.ecdfs[[x]]\$out.of.context,
        add = TRUE,
        col = "blue",
        verticals = TRUE,
        do.points = FALSE
      )
    }
    
    dev.off()
    message("Saved eCDF plots to 'amplicon_ecdfs_plot.pdf'")
    
    # ------------------------------------------------------------------------------
    # --- Export summary statistics of the eCDFs ---
    # ------------------------------------------------------------------------------
    message("Exporting summary statistics...")
    summary_list <- lapply(seq_along(amplicon.ecdfs), function(i) {
      name <- names(amplicon.ecdfs)[i]
      if (is.na(name)) name <- "unmatched"
      
      ecdf_context <- amplicon.ecdfs[[i]]\$context
      ecdf_out <- amplicon.ecdfs[[i]]\$out.of.context
      
      # Evaluate eCDF at key thresholds (e.g., 0.1, 0.5, 0.9)
      val_context_0.1 <- if (!is.null(ecdf_context)) ecdf_context(0.1) else NA
      val_context_0.5 <- if (!is.null(ecdf_context)) ecdf_context(0.5) else NA
      val_context_0.9 <- if (!is.null(ecdf_context)) ecdf_context(0.9) else NA
      
      val_out_0.1 <- if (!is.null(ecdf_out)) ecdf_out(0.1) else NA
      val_out_0.5 <- if (!is.null(ecdf_out)) ecdf_out(0.5) else NA
      val_out_0.9 <- if (!is.null(ecdf_out)) ecdf_out(0.9) else NA
      
      data.frame(
        Region = name,
        eCDF_context_at_0.1 = val_context_0.1,
        eCDF_context_at_0.5 = val_context_0.5,
        eCDF_context_at_0.9 = val_context_0.9,
        eCDF_out_of_context_at_0.1 = val_out_0.1,
        eCDF_out_of_context_at_0.5 = val_out_0.5,
        eCDF_out_of_context_at_0.9 = val_out_0.9,
        stringsAsFactors = FALSE
      )
    })
    
    summary_df <- do.call(rbind, summary_list)
    write.csv(summary_df, file = "amplicon_ecdfs_summary.csv", row.names = FALSE)
    message("Saved summary table to 'amplicon_ecdfs_summary.csv'")
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_EPIALLELER_METHYLATION_BIMODALITY_ECDF":',
        paste0('        epialleler: ', as.character(packageVersion("epialleler")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_methylation_bimodality_ecdf.csv versions.yml
    """
}

workflow BIOC_EPIALLELER_METHYLATION_BIMODALITY_ECDF_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ amplicon010meth.bam, amplicon.bed ] ]

    main:
    BIOC_EPIALLELER_METHYLATION_BIMODALITY_ECDF(ch_input)

    emit:
    tables   = BIOC_EPIALLELER_METHYLATION_BIMODALITY_ECDF.out.tables
    plots    = BIOC_EPIALLELER_METHYLATION_BIMODALITY_ECDF.out.plots
    objects  = BIOC_EPIALLELER_METHYLATION_BIMODALITY_ECDF.out.objects
    versions = BIOC_EPIALLELER_METHYLATION_BIMODALITY_ECDF.out.versions
}
