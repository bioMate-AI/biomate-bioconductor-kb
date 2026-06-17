#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: fishalyser — manual_threshold_and_cleanup
// Manually compute probe/cell masks and clean up artifacts using thresholding and particle analysis to determine optimal size parameters.
// Input: SampleFISHgray.jpg
// Container: quay.io/biocontainers/bioconductor-fishalyser:1.44.0--r45hdfd78af_0
// R packages: FISHalyseR, knitr
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FISHALYSER_MANUAL_THRESHOLD_AND_CLEANUP {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-fishalyser:1.44.0--r45hdfd78af_0"

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
    .bm_deps <- c("FISHalyseR", "knitr")
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
    library(FISHalyseR)
    
    # Input file
    f <- "SampleFISHgray.jpg"
    
    if (!file.exists(f)) {
      stop(paste("Input file", f, "not found in the working directory."))
    }
    
    # ---------------------------------------------------------
    # --- Compute Probe Mask using Max Entropy Threshold ---
    # ---------------------------------------------------------
    img = readImage(f)
    
    t = calculateMaxEntropy(img)
    img[img<t] <- 0
    img[img>=t] <- 1
    
    # Save intermediate probe mask
    fProbes1 = "exImgMaxEntropyProbes1.jpg"
    writeImage(img, fProbes1)
    
    # ---------------------------------------------------------
    # --- Clean up Probe Mask (Remove small/large particles) ---
    # ---------------------------------------------------------
    img = readImage(fProbes1)
    
    anaImg <- analyseParticles(img, 20, 5,0)
    writeImage(anaImg, "exImgProbes1Clean.jpg")
    
    # ---------------------------------------------------------
    # --- Compute Cell Mask using Otsu Threshold ---
    # ---------------------------------------------------------
    img = readImage(f)
    
    t = calculateThreshold(img)
    img[img<t] <- 0
    img[img>=t] <- 1
    
    # Save intermediate cell mask
    fCellMask = "exImgOtsuCellMask.jpg"
    writeImage(img, fCellMask)
    
    # ---------------------------------------------------------
    # --- Clean up Cell Mask (Remove small/large particles) ---
    # ---------------------------------------------------------
    img = readImage(fCellMask)
    
    anaImg <- analyseParticles(img, 20000, 1000,0)
    writeImage(anaImg, "exImgCellMaskClean.jpg")
    
    # ---------------------------------------------------------
    # --- Generate Summary and Outputs ---
    # ---------------------------------------------------------
    probe_mask_clean <- readImage("exImgProbes1Clean.jpg")
    cell_mask_clean <- readImage("exImgCellMaskClean.jpg")
    
    probe_pixels <- sum(probe_mask_clean > 0)
    cell_pixels <- sum(cell_mask_clean > 0)
    
    summary_df <- data.frame(
      Metric = c("Total_Probe_Pixels", "Total_Cell_Pixels"),
      Value = c(probe_pixels, cell_pixels)
    )
    
    write.csv(summary_df, "mask_summary.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_FISHALYSER_MANUAL_THRESHOLD_AND_CLEANUP":',
        paste0('        fishalyser: ', as.character(packageVersion("fishalyser")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_manual_threshold_and_cleanup.csv versions.yml
    """
}

workflow BIOC_FISHALYSER_MANUAL_THRESHOLD_AND_CLEANUP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ SampleFISHgray.jpg ] ]

    main:
    BIOC_FISHALYSER_MANUAL_THRESHOLD_AND_CLEANUP(ch_input)

    emit:
    tables   = BIOC_FISHALYSER_MANUAL_THRESHOLD_AND_CLEANUP.out.tables
    plots    = BIOC_FISHALYSER_MANUAL_THRESHOLD_AND_CLEANUP.out.plots
    objects  = BIOC_FISHALYSER_MANUAL_THRESHOLD_AND_CLEANUP.out.objects
    versions = BIOC_FISHALYSER_MANUAL_THRESHOLD_AND_CLEANUP.out.versions
}
