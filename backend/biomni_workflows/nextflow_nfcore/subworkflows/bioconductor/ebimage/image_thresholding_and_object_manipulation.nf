#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ebimage — image_thresholding_and_object_manipulation
// Perform global thresholding, connected component labeling, watershed segmentation, and object removal/manipulation on images.
// Input: shapes.png, nuclei.tif
// Container: quay.io/biocontainers/bioconductor-ebimage:4.52.0--r45ha27e39d_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EBIMAGE_IMAGE_THRESHOLDING_AND_OBJECT_MANIPULATION {
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
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load the EBImage library
    library(EBImage)
    
    # Set display option to raster to avoid opening a web browser in non-interactive sessions
    options(EBImage.display = "raster")
    
    # 1. Load images from the working directory
    nuc = readImage("nuclei.tif")
    shapes = readImage("shapes.png")
    
    # 2. Calculate optimal global threshold using Otsu's method
    threshold = otsu(nuc)
    
    # 3. Apply threshold to split frames and combine back
    nuc_th = combine( mapply(function(frame, th) frame > th, getFrames(nuc), threshold, SIMPLIFY=FALSE) )
    display(nuc_th, all=TRUE)
    
    # 4. Label connected components
    logo = shapes[110:512,1:130]
    logo_label = bwlabel(logo)
    display( colorLabels(logo_label) )
    
    # 5. Separate touching objects using distance transform and watershed
    nmask = watershed( distmap(nuc_th), 2 )
    display(colorLabels(nmask), all=TRUE)
    
    # 6. Remove specific objects from the mask
    objects = list(
        seq.int(from = 2, to = max(logo_label), by = 2),
        seq.int(from = 1, to = max(logo_label), by = 2)
        )
    logos = combine(logo_label, logo_label)
    z = rmObjects(logos, objects, reenumerate=FALSE)
    display(z, all=TRUE)
    
    # Write named output files for the meaningful results
    writeImage(nuc_th, "nuc_thresholded.png")
    writeImage(colorLabels(logo_label), "logo_labelled.png")
    writeImage(colorLabels(nmask), "nmask_watershed.png")
    writeImage(z, "logos_removed.png")
    
    saveRDS(threshold, "otsu_threshold.rds")
    saveRDS(nuc_th, "nuc_th.rds")
    saveRDS(logo_label, "logo_label.rds")
    saveRDS(nmask, "nmask.rds")
    saveRDS(z, "z_removed.rds")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_EBIMAGE_IMAGE_THRESHOLDING_AND_OBJECT_MANIPULATION":
        ebimage: \$(Rscript -e 'cat(as.character(packageVersion("ebimage")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_image_thresholding_and_object_manipulation.csv versions.yml
    """
}

workflow BIOC_EBIMAGE_IMAGE_THRESHOLDING_AND_OBJECT_MANIPULATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ shapes.png, nuclei.tif ] ]

    main:
    BIOC_EBIMAGE_IMAGE_THRESHOLDING_AND_OBJECT_MANIPULATION(ch_input)

    emit:
    tables   = BIOC_EBIMAGE_IMAGE_THRESHOLDING_AND_OBJECT_MANIPULATION.out.tables
    plots    = BIOC_EBIMAGE_IMAGE_THRESHOLDING_AND_OBJECT_MANIPULATION.out.plots
    objects  = BIOC_EBIMAGE_IMAGE_THRESHOLDING_AND_OBJECT_MANIPULATION.out.objects
    versions = BIOC_EBIMAGE_IMAGE_THRESHOLDING_AND_OBJECT_MANIPULATION.out.versions
}
