#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: spatialHeatmap — spatial_single_cell_covisualization
// Co-visualize spatially resolved single-cell (SRSC) data (e.g., 10X Visium) with anatomical spatial heatmaps.
// Input: spatial_single_cell.rds, bulk_data.rds, anatomical_map_sp.svg
// Container: quay.io/biocontainers/bioconductor-spatialheatmap:2.16.3--r45hdfd78af_0
// R packages: Seurat, SummarizedExperiment, ggplot2, spatialHeatmap
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPATIALHEATMAP_SPATIAL_SINGLE_CELL_COVISUALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-spatialheatmap:2.16.3--r45hdfd78af_0"

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
    .bm_deps <- c("Seurat", "SummarizedExperiment", "ggplot2", "spatialHeatmap")
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
    library(spatialHeatmap)
    library(Seurat)
    library(SummarizedExperiment)
    library(ggplot2)
    
    # --- Import the spatial aSVG image with srsc=TRUE using ---
    # Reading from the declared user input file: anatomical_map_sp.svg
    svg.mus.sp <- read_svg("anatomical_map_sp.svg", srsc=TRUE)
    
    # --- Rotate spatial coordinates if necessary by modifying the ---
    angle(svg.mus.sp)[[1]] <- angle(svg.mus.sp)[[1]] + 90
    
    # --- Define the cell-cluster-to-tissue association list ---
    lis.match <- list(cerebral.cortex=c('clus1', 'clus3', 'clus5', 'clus10', 'clus14'))
    
    # Read the other declared user input files
    srt.sc <- readRDS("spatial_single_cell.rds")
    blk.sp <- readRDS("bulk_data.rds")
    
    # --- Store objects in an SPHM container ---
    dat.srsc <- SPHM(svg=svg.mus.sp, bulk=blk.sp, cell=srt.sc, match=lis.match)
    
    # --- Generate the composite co-visualization plot using covis ---
    covis_plot <- covis(
      data=dat.srsc, 
      ID='Epha4', 
      assay.na='logcounts', 
      dimred='TSNE', 
      cell.group='seurat_clusters', 
      tar.bulk=c('cerebral.cortex'), 
      col.idp=TRUE, 
      image='anterior1', 
      bar.width=0.07, 
      dim.lgd.nrow=2, 
      dim.lgd.text.size=8, 
      legend.r=0.1, 
      legend.key.size=0.013, 
      legend.text.size=10, 
      legend.nrow=3, 
      h=0.6, 
      profile=TRUE, 
      ncol=3, 
      vjust=5, 
      dim.lgd.key.size=3, 
      size.r=0.97, 
      dim.axis.font.size=8, 
      size.pt=1.5, 
      lgd.plots.size=c(0.35, 0.25, 0.35), 
      verbose=FALSE
    )
    
    # Save outputs
    saveRDS(dat.srsc, "sphm_container.rds")
    saveRDS(covis_plot, "covis_output.rds")
    
    # Save the plot to PDF
    pdf("covis_plot.pdf", width=14, height=10)
    tryCatch({
      if (inherits(covis_plot, "ggplot") || inherits(covis_plot, "grob")) {
        plot(covis_plot)
      } else {
        print(covis_plot)
      }
    }, error = function(e) {
      warning("Could not print plot directly: ", e\$message)
    })
    dev.off()

    writeLines(c(
        '"BIOC_SPATIALHEATMAP_SPATIAL_SINGLE_CELL_COVISUALIZATION":',
        paste0('        spatialHeatmap: ', as.character(packageVersion("spatialHeatmap")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spatial_single_cell_covisualization.csv versions.yml
    """
}

workflow BIOC_SPATIALHEATMAP_SPATIAL_SINGLE_CELL_COVISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ spatial_single_cell.rds, bulk_data.rds, anatomical_map_sp.svg ] ]

    main:
    BIOC_SPATIALHEATMAP_SPATIAL_SINGLE_CELL_COVISUALIZATION(ch_input)

    emit:
    tables   = BIOC_SPATIALHEATMAP_SPATIAL_SINGLE_CELL_COVISUALIZATION.out.tables
    plots    = BIOC_SPATIALHEATMAP_SPATIAL_SINGLE_CELL_COVISUALIZATION.out.plots
    objects  = BIOC_SPATIALHEATMAP_SPATIAL_SINGLE_CELL_COVISUALIZATION.out.objects
    versions = BIOC_SPATIALHEATMAP_SPATIAL_SINGLE_CELL_COVISUALIZATION.out.versions
}
