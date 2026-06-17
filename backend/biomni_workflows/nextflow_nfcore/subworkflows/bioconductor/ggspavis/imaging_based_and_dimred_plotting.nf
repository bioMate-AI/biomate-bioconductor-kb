#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ggspavis — imaging_based_and_dimred_plotting
// Visualize imaging-based spatial transcriptomics coordinates and reduced dimensions with text annotations.
// Input: spe_xen, spe_cos, spe_mer, spe_sta
// Container: quay.io/biocontainers/bioconductor-ggspavis:1.16.0--r45hdfd78af_0
// R packages: SpatialExperiment, ggplot2, ggspavis, patchwork
// Bioconductor: 3.20 | R: 4.4
// Requires: SpatialExperiment, ggplot2, ggspavis, patchwork
// Visualizations: UMAP plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Plot imaging-based coordinates with in_tissue = NULL using plotCoords
//  * 2. [Visualization & Output] Overlay text labels on spatial clusters using text_by in plotCoords
//  * 3. [Visualization & Output] Plot reduced dimensions (e.g., UMAP) with cluster text overlays using plotDimRed

nextflow.enable.dsl = 2

process BIOC_GGSPAVIS_IMAGING_BASED_AND_DIMRED_PLOTTING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("SpatialExperiment", "ggplot2", "ggspavis", "patchwork")
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
    library(ggspavis)
    library(SpatialExperiment)
    library(patchwork)
    library(ggplot2)
    
    # -----------------------------------------------------------------------------
    # Stage 1: Read User Input Files
    # -----------------------------------------------------------------------------
    # The pipeline reads the declared SpatialExperiment objects from the working directory.
    # We assume standard RDS format for these objects.
    spe_xen <- readRDS("spe_xen.rds")
    spe_cos <- readRDS("spe_cos.rds")
    spe_mer <- readRDS("spe_mer.rds")
    spe_sta <- readRDS("spe_sta.rds")
    
    # -----------------------------------------------------------------------------
    # Stage 2: Plot imaging-based coordinates with in_tissue = NULL using plotCoords
    # -----------------------------------------------------------------------------
    # Generate the multi-panel comparison plot for Xenium, CosMx, and MERSCOPE
    p_comparison <- plotCoords(spe_xen, annotate = "cell_area", in_tissue = NULL, pal = "magma",
                               point_size = 0.15) + ggtitle("Xenium Breast Cancer") |
                    plotCoords(spe_cos, annotate = "Area", in_tissue = NULL, pal = "plasma", 
                               point_size = 0.1) + ggtitle("CosMx Breast Cancer") |
                    plotCoords(spe_mer, annotate = "volume", in_tissue = NULL, 
                               pal = c("navyblue", "yellow"),
                               point_size = 0.05) + ggtitle("MERSCOPE Ovarian Cancer")
    
    # Save the comparison plot
    ggsave("imaging_based_coordinates_comparison.pdf", plot = p_comparison, width = 15, height = 5)
    
    # -----------------------------------------------------------------------------
    # Stage 3: Overlay text labels on spatial clusters using text_by in plotCoords
    # -----------------------------------------------------------------------------
    # Generate the STARmapPLUS spatial coordinate plot with text overlays
    p_starmap_coords <- plotCoords(spe_sta, annotate = "Main_molecular_tissue_region", in_tissue = NULL,
                                   point_size = 0.1, text_by = "Main_molecular_tissue_region",
                                   text_by_size = 4, text_by_color = "#2d2d2d")
    
    # Save the STARmapPLUS spatial plot
    ggsave("starmap_spatial_annotations.pdf", plot = p_starmap_coords, width = 7, height = 6)
    
    # -----------------------------------------------------------------------------
    # Stage 4: Plot reduced dimensions (UMAP) with cluster text overlays using plotDimRed
    # -----------------------------------------------------------------------------
    # Generate the STARmapPLUS UMAP plot with text overlays
    p_starmap_umap <- plotDimRed(spe_sta, plot_type = "UMAP",
                                 annotate = "Main_molecular_tissue_region", 
                                 text_by = "Main_molecular_tissue_region",
                                 text_by_size = 3, text_by_color = "#2d2d2d")
    
    # Save the STARmapPLUS UMAP plot
    ggsave("starmap_umap_annotations.pdf", plot = p_starmap_umap, width = 7, height = 6)

    writeLines(c(
        '"BIOC_GGSPAVIS_IMAGING_BASED_AND_DIMRED_PLOTTING":',
        paste0('    ggspavis: ', as.character(packageVersion('ggspavis')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_imaging_based_and_dimred_plotting.csv versions.yml
    """
}

workflow BIOC_GGSPAVIS_IMAGING_BASED_AND_DIMRED_PLOTTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ spe_xen, spe_cos, spe_mer, spe_sta ] ]

    main:
    BIOC_GGSPAVIS_IMAGING_BASED_AND_DIMRED_PLOTTING(ch_input)

    emit:
    tables   = BIOC_GGSPAVIS_IMAGING_BASED_AND_DIMRED_PLOTTING.out.tables
    plots    = BIOC_GGSPAVIS_IMAGING_BASED_AND_DIMRED_PLOTTING.out.plots
    objects  = BIOC_GGSPAVIS_IMAGING_BASED_AND_DIMRED_PLOTTING.out.objects
    versions = BIOC_GGSPAVIS_IMAGING_BASED_AND_DIMRED_PLOTTING.out.versions
}
