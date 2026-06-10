#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: FISHalyseR — manual_threshold_and_particle_cleaning
// Manually prototype and clean up nuclei and probe masks using custom thresholding and particle size filtering.
// Input: SampleFISHgray.jpg
// Container: quay.io/biocontainers/bioconductor-fishalyser:1.44.0--r45hdfd78af_0
// R packages: FISHalyseR
// Bioconductor: 3.20 | R: 4.4
// Requires: FISHalyseR
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read the grayscale image. 2. Calculate and apply Maximum Entropy threshold for probe mask. 3. Filter out small/large artifacts fro

nextflow.enable.dsl = 2

process BIOC_FISHALYSER_MANUAL_THRESHOLD_AND_PARTICLE_CLEANING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-imaging:3.20"

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
    .bm_deps <- c("FISHalyseR")
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
    
    # Load the required package
    library(FISHalyseR)
    
    # Define the directory for intermediate and final outputs
    TempDir <- "."
    
    # 1. Read the grayscale image from the working directory
    f <- "SampleFISHgray.jpg"
    if (!file.exists(f)) {
      stop("Input file 'SampleFISHgray.jpg' not found in the working directory.")
    }
    img <- readImage(f)
    
    # 2. Calculate and apply Maximum Entropy threshold for probe mask
    t <- calculateMaxEntropy(img)
    img[img < t] <- 0
    img[img >= t] <- 1
    
    # Save intermediate probe mask
    fProbes1 <- paste(TempDir, '/', "exImgMaxEntropyProbes1.jpg", sep='')
    writeImage(img, fProbes1)
    
    # 3. Filter out small/large artifacts from the probe mask using analyseParticles
    img <- readImage(fProbes1)
    anaImgProbes <- analyseParticles(img, 20, 5, 0)
    writeImage(anaImgProbes, paste(TempDir, "exImgProbes1Clean.jpg", sep='/'))
    
    # 4. Calculate and apply Otsu threshold for cell/nuclei mask
    img <- readImage(f)
    t <- calculateThreshold(img)
    img[img < t] <- 0
    img[img >= t] <- 1
    
    # Save intermediate cell mask
    fCellMask <- paste(TempDir, '/', "exImgOtsuCellMask.jpg", sep='')
    writeImage(img, fCellMask)
    
    # 5. Filter out small/large artifacts from the cell mask using analyseParticles
    img <- readImage(fCellMask)
    anaImgCells <- analyseParticles(img, 20000, 1000, 0)
    writeImage(anaImgCells, paste(TempDir, "exImgCellMaskClean.jpg", sep='/'))
    
    # Save RDS objects of the cleaned masks for downstream analysis
    saveRDS(anaImgProbes, file = "anaImgProbes.rds")
    saveRDS(anaImgCells, file = "anaImgCells.rds")
    
    # Generate and save a summary CSV of the thresholding and cleaning results
    probe_pixels <- sum(anaImgProbes > 0)
    cell_pixels <- sum(anaImgCells > 0)
    summary_df <- data.frame(
      Metric = c("Cleaned_Probe_Mask_Active_Pixels", "Cleaned_Cell_Mask_Active_Pixels"),
      Value = c(probe_pixels, cell_pixels)
    )
    write.csv(summary_df, file = "mask_summary.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_FISHALYSER_MANUAL_THRESHOLD_AND_PARTICLE_CLEANING":',
        paste0('    FISHalyseR: ', as.character(packageVersion('FISHalyseR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_manual_threshold_and_particle_cleaning.csv versions.yml
    """
}

workflow BIOC_FISHALYSER_MANUAL_THRESHOLD_AND_PARTICLE_CLEANING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ SampleFISHgray.jpg ] ]

    main:
    BIOC_FISHALYSER_MANUAL_THRESHOLD_AND_PARTICLE_CLEANING(ch_input)

    emit:
    tables   = BIOC_FISHALYSER_MANUAL_THRESHOLD_AND_PARTICLE_CLEANING.out.tables
    plots    = BIOC_FISHALYSER_MANUAL_THRESHOLD_AND_PARTICLE_CLEANING.out.plots
    objects  = BIOC_FISHALYSER_MANUAL_THRESHOLD_AND_PARTICLE_CLEANING.out.objects
    versions = BIOC_FISHALYSER_MANUAL_THRESHOLD_AND_PARTICLE_CLEANING.out.versions
}
