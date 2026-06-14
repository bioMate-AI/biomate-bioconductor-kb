#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: spicyR — inhomogeneity_correction_and_visualization
// Account for tissue inhomogeneity in pairwise association calculations and visually inspect cellular relationships in specific images.
// Input: kerenSPE
// Container: quay.io/biocontainers/bioconductor-spicyr:1.22.0--r45hdfd78af_0
// R packages: SpatialExperiment, SummarizedExperiment, ggplot2, spicyR
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: image plot

nextflow.enable.dsl = 2

process BIOC_SPICYR_INHOMOGENEITY_CORRECTION_AND_VISUALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-spicyr:1.22.0--r45hdfd78af_0"

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
    .bm_deps <- c("SpatialExperiment", "SummarizedExperiment", "ggplot2", "spicyR")
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
    
    # Workaround for the S4 method dispatch bug in older/specific Bioconductor versions
    library(SummarizedExperiment)
    methods::setClassUnion("ExpData", c("matrix", "dgCMatrix", "ExpressionSet", "SummarizedExperiment"))
    
    # Load required libraries
    library(spicyR)
    library(SpatialExperiment)
    library(ggplot2)
    
    # --- Read the input SpatialExperiment object from the working ---
    if (file.exists("kerenSPE")) {
      kerenSPE <- readRDS("kerenSPE")
    } else if (file.exists("kerenSPE.rds")) {
      kerenSPE <- readRDS("kerenSPE.rds")
    } else {
      stop("Required input file 'kerenSPE' or 'kerenSPE.rds' not found in the working directory.")
    }
    
    # --- Subset the spatial object to a single image (image "24") ---
    kerenSubset <- kerenSPE[, colData(kerenSPE)\$imageID == "24"]
    
    # --- Calculate pairwise associations without inhomogeneity ---
    pairwiseAssoc_null <- getPairwise(kerenSubset, 
                                      sigma = NULL, 
                                      Rs = 100) |>
      as.data.frame()
    
    val_null <- pairwiseAssoc_null[["Keratin_Tumour__Neutrophils"]]
    
    # Save the uncorrected pairwise associations to a CSV file
    write.csv(pairwiseAssoc_null, "pairwiseAssoc_no_correction.csv", row.names = TRUE)
    
    # --- Calculate pairwise associations with inhomogeneity ---
    pairwiseAssoc_corrected <- getPairwise(kerenSubset, 
                                           sigma = 20, 
                                           Rs = 100) |>
      as.data.frame()
    
    val_corrected <- pairwiseAssoc_corrected[["Keratin_Tumour__Neutrophils"]]
    
    # Save the corrected pairwise associations to a CSV file
    write.csv(pairwiseAssoc_corrected, "pairwiseAssoc_corrected.csv", row.names = TRUE)
    
    # Write a text summary comparing the two values
    summary_conn <- file("association_comparison.txt", "w")
    writeLines(c(
      "Comparison of Keratin_Tumour__Neutrophils association:",
      paste("Without inhomogeneity correction (sigma = NULL):", val_null),
      paste("With inhomogeneity correction (sigma = 20):", val_corrected)
    ), summary_conn)
    close(summary_conn)
    
    # --- Plot cell-cell relationships for the image and save to PDF ---
    pdf("cell_relationship_plot_image24.pdf", width = 8, height = 8)
    p <- plotImage(kerenSPE, "24", from = "Keratin_Tumour", to = "Neutrophils")
    if (inherits(p, "ggplot")) {
      print(p)
    }
    dev.off()

    writeLines(c(
        '"BIOC_SPICYR_INHOMOGENEITY_CORRECTION_AND_VISUALIZATION":',
        paste0('        spicyR: ', as.character(packageVersion("spicyR")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_inhomogeneity_correction_and_visualization.csv versions.yml
    """
}

workflow BIOC_SPICYR_INHOMOGENEITY_CORRECTION_AND_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ kerenSPE ] ]

    main:
    BIOC_SPICYR_INHOMOGENEITY_CORRECTION_AND_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_SPICYR_INHOMOGENEITY_CORRECTION_AND_VISUALIZATION.out.tables
    plots    = BIOC_SPICYR_INHOMOGENEITY_CORRECTION_AND_VISUALIZATION.out.plots
    objects  = BIOC_SPICYR_INHOMOGENEITY_CORRECTION_AND_VISUALIZATION.out.objects
    versions = BIOC_SPICYR_INHOMOGENEITY_CORRECTION_AND_VISUALIZATION.out.versions
}
