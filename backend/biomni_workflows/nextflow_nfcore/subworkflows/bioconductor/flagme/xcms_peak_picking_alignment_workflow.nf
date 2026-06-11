#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: flagme — xcms_peak_picking_alignment_workflow
// Read raw GC-MS data, perform peak picking and grouping using XCMS/CAMERA within R, and align peaks.
// Input: cdfFiles
// Container: quay.io/biocontainers/bioconductor-flagme:1.66.0--r45h01b2380_0
// R packages: CAMERA, flagme, xcms
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FLAGME_XCMS_PEAK_PICKING_ALIGNMENT_WORKFLOW {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-flagme:1.66.0--r45h01b2380_0"

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
    .bm_deps <- c("CAMERA", "flagme", "xcms")
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
    library(flagme)
    library(xcms)
    library(CAMERA)
    
    # 1. Identify the user input files in the working directory
    cdfFiles <- list.files(pattern = "\\\\.(cdf|CDF)\$", full.names = TRUE)
    
    if (length(cdfFiles) < 3) {
      stop("Error: This workflow requires at least 3 raw GC-MS NetCDF (.cdf or .CDF) files in the working directory.")
    }
    
    # 2. Initialize a peaksDataset object using peaksDataset
    message("Initializing peaksDataset...")
    pd.2 <- peaksDataset(cdfFiles[1:3], mz = seq(50, 550), rtrange = c(7.5, 8.5))
    
    # 3. Perform peak picking and grouping using addXCMSPeaks with xcms::MatchedFilterParam
    message("Performing peak picking and grouping with XCMS/CAMERA...")
    mfp <- xcms::MatchedFilterParam(fwhm = 10, snthresh = 5)
    pd.2 <- addXCMSPeaks(cdfFiles[1:3], pd.2, settings = mfp)
    
    # 4. Perform alignment using correlationAlignment
    message("Aligning peaks using correlationAlignment...")
    mp <- correlationAlignment(object=pd.2, thr=0.85, D=20, penality=0.2, normalize=TRUE, minFilter=1)
    
    # 5. Save meaningful results to output files
    message("Saving results...")
    
    # Save the peaksDataset and alignment objects as RDS
    saveRDS(pd.2, file = "peaks_dataset_xcms.rds")
    saveRDS(mp, file = "correlation_alignment.rds")
    
    # Export a summary table of peak counts per sample
    peak_summary <- data.frame(
      Sample = basename(cdfFiles[1:3]),
      Peak_Count = sapply(pd.2@peaksrt, length)
    )
    write.csv(peak_summary, file = "peak_counts_summary.csv", row.names = FALSE)
    
    # Generate a PDF plot of the chromatograms
    pdf("chromatogram_plot.pdf", width = 10, height = 7)
    tryCatch({
      plotChrom(pd.2, rtrange = c(7.5, 8.5), plotPeaks = TRUE, plotPeakLabels = TRUE)
    }, error = function(e) {
      warning("Could not plot chromatogram: ", e\$message)
    })
    dev.off()
    
    message("Pipeline completed successfully. Outputs written to:")
    message("- peaks_dataset_xcms.rds")
    message("- correlation_alignment.rds")
    message("- peak_counts_summary.csv")
    message("- chromatogram_plot.pdf")

    writeLines(c(
        '"BIOC_FLAGME_XCMS_PEAK_PICKING_ALIGNMENT_WORKFLOW":',
        paste0('        flagme: ', as.character(packageVersion("flagme")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_xcms_peak_picking_alignment_workflow.csv versions.yml
    """
}

workflow BIOC_FLAGME_XCMS_PEAK_PICKING_ALIGNMENT_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ cdfFiles ] ]

    main:
    BIOC_FLAGME_XCMS_PEAK_PICKING_ALIGNMENT_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_FLAGME_XCMS_PEAK_PICKING_ALIGNMENT_WORKFLOW.out.tables
    plots    = BIOC_FLAGME_XCMS_PEAK_PICKING_ALIGNMENT_WORKFLOW.out.plots
    objects  = BIOC_FLAGME_XCMS_PEAK_PICKING_ALIGNMENT_WORKFLOW.out.objects
    versions = BIOC_FLAGME_XCMS_PEAK_PICKING_ALIGNMENT_WORKFLOW.out.versions
}
