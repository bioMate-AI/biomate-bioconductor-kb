#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: imcRtools — spillover_correction
// Quantify and estimate channel spillover from single-metal spot acquisitions to correct multiplexed pixel intensities.
// Input: metal_spot.txt, metal_spot.tiff, images.csv, panel.csv
// Container: quay.io/biocontainers/bioconductor-imcrtools:1.16.0--r45hdfd78af_0
// R packages: CATALYST, SingleCellExperiment, imcRtools
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: heatmap

nextflow.enable.dsl = 2

process BIOC_IMCRTOOLS_SPILLOVER_CORRECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-imcrtools:1.16.0--r45hdfd78af_0"

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
    .bm_deps <- c("CATALYST", "SingleCellExperiment", "imcRtools", "SummarizedExperiment")
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
    library(imcRtools)
    library(SummarizedExperiment)
    library(CATALYST)
    library(SingleCellExperiment)
    
    # --- Read single-spot data using readSCEfromTXT ---
    # Create a temporary directory to hold the single-metal spot TXT file
    txt_dir <- "txt_temp_dir"
    if (!dir.exists(txt_dir)) {
      dir.create(txt_dir)
    }
    file.copy("metal_spot.txt", file.path(txt_dir, "metal_spot.txt"), overwrite = TRUE)
    
    path <- txt_dir
    sce_txt <- readSCEfromTXT(path)
    
    # --- Read single-spot data using readSCEfromTIFF ---
    # Create a temporary directory to hold the single-metal spot TIFF file
    tiff_dir <- "tiff_temp_dir"
    if (!dir.exists(tiff_dir)) {
      dir.create(tiff_dir)
    }
    file.copy("metal_spot.tiff", file.path(tiff_dir, "metal_spot.tiff"), overwrite = TRUE)
    
    path <- tiff_dir
    image_df_path <- "images.csv"
    panel_df_path <- "panel.csv"
    
    sce <- readSCEfromTIFF(path, image_df_path, panel_df_path)
    
    # --- Perform quality control visualization using ---
    pdf("spot_heatmap.pdf")
    p1 <- plotSpotHeatmap(sce)
    if (!is.null(p1)) print(p1)
    dev.off()
    
    pdf("spot_heatmap_threshold.pdf")
    p2 <- plotSpotHeatmap(sce, log = FALSE, threshold = 200)
    if (!is.null(p2)) print(p2)
    dev.off()
    
    # --- Sum consecutive pixels using binAcrossPixels to enhance ---
    sce2 <- binAcrossPixels(sce, bin_size = 5)
    
    pdf("spot_heatmap_binned.pdf")
    p3 <- plotSpotHeatmap(sce2, log = FALSE, threshold = 200)
    if (!is.null(p3)) print(p3)
    dev.off()
    
    # --- Assign and filter pixels using CATALYST functions and ---
    bc_key <- as.numeric(unique(sce\$sample_mass))
    assay(sce, "exprs") <- asinh(counts(sce)/5)
    sce <- assignPrelim(sce, bc_key = bc_key)
    sce <- estCutoffs(sce)
    sce <- applyCutoffs(sce)
    sce <- filterPixels(sce)
    
    # --- Estimate the spillover matrix using computeSpillmat ---
    sce <- computeSpillmat(sce)
    spillover_matrix <- metadata(sce)\$spillover_matrix
    
    # Write outputs to the working directory
    write.csv(as.data.frame(spillover_matrix), "spillover_matrix.csv", row.names = TRUE)
    saveRDS(sce, "sce_corrected.rds")
    saveRDS(sce_txt, "sce_txt.rds")
    
    # Clean up temporary directories
    unlink(txt_dir, recursive = TRUE)
    unlink(tiff_dir, recursive = TRUE)

    writeLines(c(
        '"BIOC_IMCRTOOLS_SPILLOVER_CORRECTION":',
        paste0('        imcRtools: ', as.character(packageVersion("imcRtools")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spillover_correction.csv versions.yml
    """
}

workflow BIOC_IMCRTOOLS_SPILLOVER_CORRECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ metal_spot.txt, metal_spot.tiff, images.csv, panel.csv ] ]

    main:
    BIOC_IMCRTOOLS_SPILLOVER_CORRECTION(ch_input)

    emit:
    tables   = BIOC_IMCRTOOLS_SPILLOVER_CORRECTION.out.tables
    plots    = BIOC_IMCRTOOLS_SPILLOVER_CORRECTION.out.plots
    objects  = BIOC_IMCRTOOLS_SPILLOVER_CORRECTION.out.objects
    versions = BIOC_IMCRTOOLS_SPILLOVER_CORRECTION.out.versions
}
