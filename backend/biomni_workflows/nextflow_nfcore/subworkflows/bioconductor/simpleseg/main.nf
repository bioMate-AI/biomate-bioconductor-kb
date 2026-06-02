#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: simpleSeg
// Image segmentation is the process of identifying the borders of individual objects (in this case cel
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/simpleSeg/inst/doc/simpleSeg.R
// Upstream  : BiocStyle
// Downstream: none
//
// Install: BiocManager::install("simpleSeg")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SIMPLESEG {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-simpleseg"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-simpleseg:1.8.1--r44_0' :
        'quay.io/biocontainers/bioconductor-simpleseg:1.8.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_simpleseg_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_simpleseg_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_simpleseg_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(simpleSeg)
    library(jsonlite)


    # --- Include = False [] ---
    # Key functions: set
    knitr::opts_chunk$set(
      collapse = TRUE,
      comment = "#>"
    )
    library(BiocStyle)

    # --- Eval = False [] ---
    # Key functions: requireNamespace, install, dir, simpleSeg, extdata
    # # Install the package from Bioconductor
    # if (!requireNamespace("BiocManager", quietly = TRUE)) {
    #   install.packages("BiocManager")
    # }
    # 
    # BiocManager::install("simpleSeg")

    ## -----------------------------------------------------------------------------
    # Get path to image directory
    pathToImages <- system.file("extdata", package = "simpleSeg")

    # Get directories of images

    imageDirs <- dir(pathToImages, "Point", full.names = TRUE)
    names(imageDirs) <- dir(pathToImages, "Point", full.names = FALSE)

    # --- Parallel Example [] ---
    # Key functions: simpleSeg
    masks <- simpleSeg::simpleSeg(images,
      nucleus = "HH3",
      cores = 1
    )

    # --- Out Width = "400px" [] ---
    # Key functions: measureObjects, normalizeCells, imageID, counts, norm, trim99, minMax
    cellSCE <- cytomapper::measureObjects(masks, images, img_id = "imageID")

    ## -----------------------------------------------------------------------------
    # Transform and normalise the marker expression of each cell type.
    # Use a square root transform, then trimmed the 99 quantile
    cellSCE <- normalizeCells(cellSCE,
      assayIn = "counts",
      assayOut = "norm",
      imageID = "imageID",
      transformation = "sqrt",
      method = c("trim99", "minMax")
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_simpleseg_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_simpleseg_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_simpleseg_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SIMPLESEG:", paste0("    simpleseg: ", packageVersion("simpleSeg"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_simpleseg_results.csv
    touch ${prefix}_simpleseg_output.rds
    echo "BIOC_SIMPLESEG:" > versions.yml
    echo "    simpleseg: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SIMPLESEG_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SIMPLESEG(ch_input)

    emit:
    results  = BIOC_SIMPLESEG.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SIMPLESEG.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SIMPLESEG.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SIMPLESEG.out.versions  // channel: path(versions.yml)
}
