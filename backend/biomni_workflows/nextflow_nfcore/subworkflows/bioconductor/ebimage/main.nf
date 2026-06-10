#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ebimage — cell_segmentation
// Segment nuclei and cell bodies from fluorescent microscopy images and visualize the segmented boundaries.
// Input: nuclei.tif, cells.tif
// Container: quay.io/biocontainers/bioconductor-ebimage:4.52.0--r45ha27e39d_0
// R packages: EBImage
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EBIMAGE_CELL_SEGMENTATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-ebimage:4.52.0--r45ha27e39d_0"

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
    .bm_deps <- c("EBImage")
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
    
    # Load required library
    library(EBImage)
    
    # Set display option to raster to avoid opening interactive browser windows
    options(EBImage.display = "raster")
    
    # 1. Load nuclei and cell body images from the working directory
    nuc = readImage('nuclei.tif')
    cel = readImage('cells.tif')
    
    # 2. Combine images into a false-color RGB image and display
    cells = rgbImage(green=1.5*cel, blue=nuc)
    display(cells, all = TRUE)
    
    # 3. Segment nuclei
    nmask = thresh(nuc, w=10, h=10, offset=0.05)
    nmask = opening(nmask, makeBrush(5, shape='disc'))
    nmask = fillHull(nmask)
    nmask = bwlabel(nmask)
    display(nmask, all=TRUE)
    
    # 4. Define cell body mask and segment cytoplasm using Voronoi tessellation (propagate)
    ctmask = opening(cel>0.1, makeBrush(5, shape='disc'))
    cmask = propagate(cel, seeds=nmask, mask=ctmask)
    display(ctmask, all=TRUE)
    
    # 5. Highlight and visualize segmented nuclei and cell boundaries
    segmented = paintObjects(cmask, cells, col='#ff00ff')
    segmented = paintObjects(nmask, segmented, col='#ffff00')
    display(segmented, all=TRUE)
    
    # 6. Save meaningful results to output files
    # Save the final segmented visualization as an image
    writeImage(segmented, "segmented_cells.png")
    
    # Save the binary/labeled masks as RDS objects for downstream analysis
    saveRDS(nmask, "nuclei_mask.rds")
    saveRDS(cmask, "cell_mask.rds")
    
    # Compute and save basic morphometric statistics (cell and nuclei sizes)
    cell_ids = unique(as.vector(cmask))
    cell_ids = cell_ids[cell_ids > 0] # exclude background
    
    cell_sizes = table(cmask[cmask > 0])
    nuclei_sizes = table(nmask[nmask > 0])
    
    # Align sizes by ID (some nuclei might not have corresponding propagated cell bodies or vice versa)
    common_ids = intersect(names(cell_sizes), names(nuclei_sizes))
    
    summary_df = data.frame(
      object_id = as.integer(common_ids),
      nucleus_area_pixels = as.integer(nuclei_sizes[common_ids]),
      cell_area_pixels = as.integer(cell_sizes[common_ids])
    )
    
    write.csv(summary_df, "segmentation_quantification.csv", row.names = FALSE)

    cat <<-END_VERSIONS > versions.yml
    "BIOC_EBIMAGE_CELL_SEGMENTATION":
        ebimage: \$(Rscript -e 'cat(as.character(packageVersion("ebimage")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cell_segmentation.csv versions.yml
    """
}

workflow BIOC_EBIMAGE_CELL_SEGMENTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ nuclei.tif, cells.tif ] ]

    main:
    BIOC_EBIMAGE_CELL_SEGMENTATION(ch_input)

    emit:
    tables   = BIOC_EBIMAGE_CELL_SEGMENTATION.out.tables
    plots    = BIOC_EBIMAGE_CELL_SEGMENTATION.out.plots
    objects  = BIOC_EBIMAGE_CELL_SEGMENTATION.out.objects
    versions = BIOC_EBIMAGE_CELL_SEGMENTATION.out.versions
}
