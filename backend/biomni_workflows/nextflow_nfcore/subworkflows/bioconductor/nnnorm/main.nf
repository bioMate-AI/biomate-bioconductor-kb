#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: nnNorm — microarray_spatial_intensity_normalization
// Detect and correct spatial and intensity biases in two-channel microarray data using robust neural networks.
// Input: microarray_data.marrayRaw
// Container: quay.io/biocontainers/bioconductor-nnnorm:2.74.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: marray, nnNorm
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the raw microarray data
//  * 2. [Core Analysis] Perform neural network normalization using maNormNN to obtain normalized log ratios

nextflow.enable.dsl = 2

process BIOC_NNNORM_MICROARRAY_SPATIAL_INTENSITY_NORMALIZATION {
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("marray", "nnNorm")
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
            library(marray)
            library(nnNorm)
            
            # 1. Load the raw microarray data
            # The user input is a serialized marrayRaw object
            swirl <- readRDS("microarray_data.marrayRaw")
            
            # 2. Perform neural network normalization using maNormNN to obtain normalized log ratios
            swirl_n <- maNormNN(swirl)
            
            # 3. Save the meaningful results
            # Save the normalized marrayNorm object
            saveRDS(swirl_n, "normalized_data.rds")
            
            # Extract and save the normalized log ratios (M) and average intensities (A)
            normalized_M <- maM(swirl_n)
            normalized_A <- maA(swirl_n)
            
            write.csv(normalized_M, "normalized_log_ratios_M.csv", row.names = TRUE)
            write.csv(normalized_A, "average_intensities_A.csv", row.names = TRUE)
            
            # Generate diagnostic MA-plots for the normalized arrays
            pdf("normalization_plots.pdf", width = 10, height = 5)
            par(mfrow = c(1, 2))
            num_arrays <- maNsamples(swirl_n)
            for (i in 1:num_arrays) {
              maPlot(swirl_n[, i], main = paste("Normalized Array", i))
            }
            dev.off()

    writeLines(c(
        '"BIOC_NNNORM_MICROARRAY_SPATIAL_INTENSITY_NORMALIZATION":',
        paste0('    nnNorm: ', as.character(packageVersion('nnNorm')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_microarray_spatial_intensity_normalization.csv versions.yml
    """
}

workflow BIOC_NNNORM_MICROARRAY_SPATIAL_INTENSITY_NORMALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ microarray_data.marrayRaw ] ]

    main:
    BIOC_NNNORM_MICROARRAY_SPATIAL_INTENSITY_NORMALIZATION(ch_input)

    emit:
    tables   = BIOC_NNNORM_MICROARRAY_SPATIAL_INTENSITY_NORMALIZATION.out.tables
    plots    = BIOC_NNNORM_MICROARRAY_SPATIAL_INTENSITY_NORMALIZATION.out.plots
    objects  = BIOC_NNNORM_MICROARRAY_SPATIAL_INTENSITY_NORMALIZATION.out.objects
    versions = BIOC_NNNORM_MICROARRAY_SPATIAL_INTENSITY_NORMALIZATION.out.versions
}
