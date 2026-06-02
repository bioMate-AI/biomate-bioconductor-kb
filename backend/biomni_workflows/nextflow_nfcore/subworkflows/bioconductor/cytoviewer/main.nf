#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: cytoviewer
// This R package supports interactive visualization of multi-channel images and segmentation masks gen
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/cytoviewer/inst/doc/cytoviewer.R
// Upstream  : cytomapper
// Downstream: none
//
// Install: BiocManager::install("cytoviewer")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CYTOVIEWER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cytoviewer"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cytoviewer:1.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cytoviewer:1.6.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cytoviewer_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cytoviewer_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cytoviewer_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(cytoviewer)
    library(jsonlite)


    # --- Dataset [] ---
    # Key functions: pancreasImages, pancreasMasks, pancreasSCE
    # Load example datasets 
    library(cytomapper)
    data("pancreasImages")
    data("pancreasMasks")
    data("pancreasSCE")

    pancreasImages
    pancreasMasks 
    pancreasSCE

    # --- Cytoviewer [] ---
    # Key functions: cytoviewer, interactive, runApp
    # Use cytoviewer with images, masks and object
    app <- cytoviewer(image = pancreasImages, 
                      mask = pancreasMasks, 
                      object = pancreasSCE, 
                      img_id = "ImageNb", 
                      cell_id = "CellNb")

    if (interactive()) {

      shiny::runApp(app, launch.browser = TRUE)

      }

    ## ----read-in-images-----------------------------------------------------------
    library(cytomapper)

    # --- Measure Objects [] ---
    # Key functions: measureObjects, cytoviewer, interactive, object_id
    cur_sce <- measureObjects(image = cur_images, 
                              mask = cur_masks, 
                              img_id = "ImageNb")
    cur_sce

    ## ----cytoviewer-manual--------------------------------------------------------
    # Use cytoviewer with images, masks and object
    app_1 <- cytoviewer(image = cur_images, 
                      mask = cur_masks, 
                      object = cur_sce, 
                      img_id = "ImageNb", 
                      cell_id = "object_id")


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cytoviewer_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cytoviewer_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cytoviewer_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CYTOVIEWER:", paste0("    cytoviewer: ", packageVersion("cytoviewer"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cytoviewer_results.csv
    touch ${prefix}_cytoviewer_output.rds
    echo "BIOC_CYTOVIEWER:" > versions.yml
    echo "    cytoviewer: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CYTOVIEWER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CYTOVIEWER(ch_input)

    emit:
    results  = BIOC_CYTOVIEWER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CYTOVIEWER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CYTOVIEWER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CYTOVIEWER.out.versions  // channel: path(versions.yml)
}
