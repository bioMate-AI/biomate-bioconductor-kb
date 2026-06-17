#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ggspavis — spatial_coordinate_and_visium_plotting
// Visualize spatial coordinates, gene expression, and histology overlays for sequencing-based spatial transcriptomics data.
// Input: spe_slide, spe_vm, spe, vhd8
// Container: quay.io/biocontainers/bioconductor-ggspavis:1.16.0--r45hdfd78af_0
// R packages: SpatialExperiment, ggplot2, ggspavis, patchwork, scater, stexampledata
// Bioconductor: 3.20 | R: 4.4
// Requires: SpatialExperiment, SummarizedExperiment, ggplot2, ggspavis, patchwork
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Plot spatial coordinates for Slide-seq data using plotCoords
//  * 2. [Visualization & Output] Plot Visium spots overlaid on histology using plotVisium
//  * 3. [Visualization & Output] Plot gene expression spatially using plotVisium and plotCoords
//  * 4. [Visualization & Output] Plot Visium spots without histology or histology without spots
//  * 5. [Visualization & Output] Plot categorical annotations using custom palettes
//  * 6. [Visualization & Output] Plot Visium HD square bins using custom point shapes

nextflow.enable.dsl = 2

process BIOC_GGSPAVIS_SPATIAL_COORDINATE_AND_VISIUM_PLOTTING {
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
    .bm_deps <- c("SpatialExperiment", "ggplot2", "ggspavis", "patchwork", "scater", "stexampledata", "SummarizedExperiment")
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
    library(ggspavis)
    library(SummarizedExperiment)
    library(patchwork)
    library(ggplot2)
    library(SpatialExperiment)
    
    # -----------------------------------------------------------------------------
    # 1. Load User Input Files
    # -----------------------------------------------------------------------------
    # The pipeline reads exactly these files from the working directory.
    spe_slide <- readRDS("spe_slide.rds")
    spe_vm    <- readRDS("spe_vm.rds")
    spe       <- readRDS("spe.rds")
    vhd8      <- readRDS("vhd8.rds")
    
    # -----------------------------------------------------------------------------
    # 2. Preprocessing / Object Preparation
    # -----------------------------------------------------------------------------
    # Prepare Slide-seq V2 object
    if (!"loglibsize" %in% colnames(colData(spe_slide))) {
      spe_slide\$loglibsize <- log1p(colSums(SummarizedExperiment::assay(spe_slide, "counts")))
    }
    
    # Prepare Visium mouse coronal object
    if (!is.null(rowData(spe_vm)\$gene_name)) {
      rownames(spe_vm) <- rowData(spe_vm)\$gene_name
    }
    spe_vm\$sum <- colSums(SummarizedExperiment::assay(spe_vm, "counts"))
    
    # Prepare Visium human DLPFC object
    if (!is.null(rowData(spe)\$gene_name)) {
      rownames(spe) <- rowData(spe)\$gene_name
    }
    spe\$libsize <- colSums(SummarizedExperiment::assay(spe, "counts"))
    
    # Prepare Visium HD object
    if (!is.null(rowData(vhd8)\$Symbol)) {
      rownames(vhd8) <- rowData(vhd8)\$Symbol
    }
    
    # -----------------------------------------------------------------------------
    # 3. Execute Documented Visualization Workflow & Save Outputs
    # -----------------------------------------------------------------------------
    
    # Stage 1: Plot spatial coordinates for Slide-seq data using plotCoords
    pdf("plot_1_slideseq_coords.pdf", width = 10, height = 4)
    p_slide <- (plotCoords(spe_slide, annotate = "celltype", 
                in_tissue = NULL, point_size = 0.1) + 
      guides(color=guide_legend(override.aes = list(size = 3), ncol = 2)) |
      plotCoords(spe_slide, annotate = "loglibsize", 
                 in_tissue = NULL, point_size = 0.1) + 
      scale_color_gradient(name = "Log library size") + ggtitle("")) +
      plot_annotation(title = 'Slide-seq V2 Mouse Brain')
    print(p_slide)
    dev.off()
    
    # Stage 2: Plot Visium spots overlaid on histology using plotVisium (Library Size)
    pdf("plot_2_visium_vm_libsize.pdf", width = 8, height = 4)
    p1 <- plotVisium(spe_vm, annotate = "sum", highlight = "in_tissue", 
                     legend_position = "none")
    p2 <- plotVisium(spe_vm, annotate = "sum", highlight = "in_tissue", 
                     pal = "darkred") + 
      guides(fill = guide_colorbar(title = "Libsize"))
    print(p1 | p2)
    dev.off()
    
    # Stage 3: Plot gene expression spatially using plotVisium
    pdf("plot_3_visium_vm_genes.pdf", width = 8, height = 4)
    p1 <- plotVisium(spe_vm, annotate = "Gapdh", highlight = "in_tissue")
    p2 <- plotVisium(spe_vm, annotate = "Mbp", highlight = "in_tissue")
    print(p1 | p2)
    dev.off()
    
    # Stage 4: Plot Visium spots without histology or histology without spots
    pdf("plot_4_visium_vm_spots_vs_image.pdf", width = 8, height = 4)
    p1 <- plotVisium(spe_vm, annotate = "Mbp", 
                     highlight = "in_tissue", image = FALSE)
    p2 <- plotVisium(spe_vm, annotate = "Mbp", 
                     highlight = "in_tissue", spots = FALSE)
    print(p1 | p2)
    dev.off()
    
    # Stage 3 (cont.): Plot gene expression spatially using plotCoords
    pdf("plot_5_coords_vm_genes.pdf", width = 8, height = 4)
    p1 <- plotCoords(spe_vm, annotate = "Gapdh")
    p2 <- plotCoords(spe_vm, annotate = "Mbp", pal = "viridis")
    print(p1 | p2)
    dev.off()
    
    # Stage 5: Plot categorical annotations using custom palettes (Visium DLPFC)
    pdf("plot_6_visium_spe_ground_truth.pdf", width = 6, height = 5)
    p_gt <- plotVisium(spe, annotate = "ground_truth", highlight = "in_tissue", 
               pal = "libd_layer_colors")
    print(p_gt)
    dev.off()
    
    pdf("plot_7_coords_spe_palettes.pdf", width = 8, height = 4)
    p1 <- plotCoords(spe, annotate = "ground_truth", pal = "Okabe-Ito") +
      ggtitle("Reference")
    p2 <- plotCoords(spe, annotate = "libsize", pal = "rainbow") + 
      ggtitle("Library size")
    print(p1 | p2)
    dev.off()
    
    # Stage 6: Plot Visium HD square bins using custom point shapes
    pdf("plot_8_visium_hd_vhd8.pdf", width = 10, height = 5)
    p_hd <- plotCoords(vhd8, point_shape=15, point_size = 1.7, annotate="PIGR") | 
      plotVisium(vhd8, point_shape=22, point_size = 2, annotate="PIGR", 
               zoom = TRUE)
    print(p_hd)
    dev.off()

    writeLines(c(
        '"BIOC_GGSPAVIS_SPATIAL_COORDINATE_AND_VISIUM_PLOTTING":',
        paste0('    ggspavis: ', as.character(packageVersion('ggspavis')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spatial_coordinate_and_visium_plotting.csv versions.yml
    """
}

workflow BIOC_GGSPAVIS_SPATIAL_COORDINATE_AND_VISIUM_PLOTTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ spe_slide, spe_vm, spe, vhd8 ] ]

    main:
    BIOC_GGSPAVIS_SPATIAL_COORDINATE_AND_VISIUM_PLOTTING(ch_input)

    emit:
    tables   = BIOC_GGSPAVIS_SPATIAL_COORDINATE_AND_VISIUM_PLOTTING.out.tables
    plots    = BIOC_GGSPAVIS_SPATIAL_COORDINATE_AND_VISIUM_PLOTTING.out.plots
    objects  = BIOC_GGSPAVIS_SPATIAL_COORDINATE_AND_VISIUM_PLOTTING.out.objects
    versions = BIOC_GGSPAVIS_SPATIAL_COORDINATE_AND_VISIUM_PLOTTING.out.versions
}
