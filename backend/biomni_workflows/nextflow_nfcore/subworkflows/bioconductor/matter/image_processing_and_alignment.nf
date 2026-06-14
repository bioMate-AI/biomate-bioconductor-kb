#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: matter — image_processing_and_alignment
// Smooth, enhance contrast, and warp/co-register 2D images.
// Input: image_matrix.rds
// Container: quay.io/biocontainers/bioconductor-matter:2.12.0--r45ha27e39d_0
// R packages: matter
// Bioconductor: 3.20 | R: 4.4
// Requires: matter
// Visualizations: image plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Smooth 2D images using filt2_* functions
//  * 2. [Core Analysis] Enhance image contrast using enhance_* functions
//  * 3. [Core Analysis] Warp and co-register images using warp2_trans
//  * 4. [Core Analysis] Detect 2D local maxima using knnmax

nextflow.enable.dsl = 2

process BIOC_MATTER_IMAGE_PROCESSING_AND_ALIGNMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-imaging:3.20-deps"

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
    .bm_deps <- c("matter")
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
    library(matter)
    
    # 1. Load User Input
    if (!file.exists("image_matrix.rds")) {
      stop("Error: 'image_matrix.rds' not found in the working directory.")
    }
    img_base <- readRDS("image_matrix.rds")
    
    # Ensure the input is a matrix
    img_base <- as.matrix(img_base)
    
    # Stage 1: Smooth 2D images using filt2_* functions
    set.seed(1)
    img <- img_base + rnorm(length(img_base), sd=2.5)
    
    f_ma <- filt2_ma(img)
    f_gauss <- filt2_gauss(img)
    f_bi <- filt2_bi(img)
    f_diff <- filt2_diff(img)
    f_guide <- filt2_guide(img)
    
    # Save smoothed results
    smoothed_results <- list(
      original_noisy = img,
      moving_average = f_ma,
      gaussian = f_gauss,
      bilateral = f_bi,
      diffusion = f_diff,
      guided = f_guide
    )
    saveRDS(smoothed_results, "smoothed_images.rds")
    
    # Stage 2: Enhance image contrast using enhance_* functions
    set.seed(1)
    img <- img_base + rlnorm(length(img_base), sd=1.5)
    
    e_adj <- enhance_adj(img)
    e_hist <- enhance_hist(img)
    e_adapt <- enhance_adapt(img)
    
    # Save enhanced results
    enhanced_results <- list(
      original_noisy = img,
      adjusted = e_adj,
      histogram = e_hist,
      clahe = e_adapt
    )
    saveRDS(enhanced_results, "enhanced_images.rds")
    
    # Stage 3: Warp and co-register images using warp2_trans
    img1 <- trans2d(img_base, rotate=15, translate=c(-5, 5))
    img2 <- warp2_trans(img1, img_base)
    
    # Save warped results
    warped_results <- list(
      original = img_base,
      transformed = img1,
      warped = img2
    )
    saveRDS(warped_results, "warped_image.rds")
    
    # Stage 4: Detect 2D local maxima using knnmax
    img <- img_base
    coord <- expand.grid(lapply(dim(img), seq_len))
    
    i <- knnmax(img, index=coord, k=49)
    i <- which(i, arr.ind=TRUE)
    
    # Save local maxima coordinates
    write.csv(as.data.frame(i), "local_maxima.csv", row.names=FALSE)
    
    # Generate PDF plots of the workflow stages
    pdf("image_processing_pipeline_plots.pdf", width=10, height=8)
    par(mfrow=c(2, 3))
    
    # Plot original vs smoothed
    image(img_base, main="Original Image", col=terrain.colors(100))
    image(smoothed_results\$original_noisy, main="Noisy Image (for smoothing)", col=terrain.colors(100))
    image(smoothed_results\$guided, main="Guided Filtered", col=terrain.colors(100))
    
    # Plot contrast enhancement
    image(enhanced_results\$original_noisy, main="Noisy Image (for contrast)", col=terrain.colors(100))
    image(enhanced_results\$clahe, main="CLAHE Enhanced", col=terrain.colors(100))
    
    # Plot warping
    image(warped_results\$transformed, main="Transformed (Rotated/Translated)", col=terrain.colors(100))
    image(warped_results\$warped, main="Warped/Co-registered", col=terrain.colors(100))
    
    # Plot local maxima
    image(img_base, main="Local Maxima (Red Crosses)", col=terrain.colors(100))
    if (nrow(i) > 0) {
      # Scale coordinates to [0, 1] for base R image() plotting compatibility
      x_scaled <- (i[, 1] - 1) / (nrow(img_base) - 1)
      y_scaled <- (i[, 2] - 1) / (ncol(img_base) - 1)
      points(x_scaled, y_scaled, col="red", pch=4, lwd=1.5, cex=0.8)
    }
    
    dev.off()
    
    cat("Pipeline completed successfully. Outputs saved to 'smoothed_images.rds', 'enhanced_images.rds', 'warped_image.rds', 'local_maxima.csv', and 'image_processing_pipeline_plots.pdf'.\n")

    writeLines(c(
        '"BIOC_MATTER_IMAGE_PROCESSING_AND_ALIGNMENT":',
        paste0('    matter: ', as.character(packageVersion('matter')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_image_processing_and_alignment.csv versions.yml
    """
}

workflow BIOC_MATTER_IMAGE_PROCESSING_AND_ALIGNMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ image_matrix.rds ] ]

    main:
    BIOC_MATTER_IMAGE_PROCESSING_AND_ALIGNMENT(ch_input)

    emit:
    tables   = BIOC_MATTER_IMAGE_PROCESSING_AND_ALIGNMENT.out.tables
    plots    = BIOC_MATTER_IMAGE_PROCESSING_AND_ALIGNMENT.out.plots
    objects  = BIOC_MATTER_IMAGE_PROCESSING_AND_ALIGNMENT.out.objects
    versions = BIOC_MATTER_IMAGE_PROCESSING_AND_ALIGNMENT.out.versions
}
