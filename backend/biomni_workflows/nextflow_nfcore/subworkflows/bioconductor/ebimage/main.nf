#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: EBImage
// EBImage provides general purpose functionality for image processing and analysis. In the context of 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/EBImage/inst/doc/EBImage-introduction.R
// Upstream  : none
// Downstream: CRImage, cytomapper, flowcatchR, DonaPLLP2013, furrowSeg
//
// Install: BiocManager::install("EBImage")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EBIMAGE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ebimage"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ebimage:4.48.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ebimage:4.48.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ebimage_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ebimage_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ebimage_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(EBImage)
    library(jsonlite)

    # --- Display analysis [] ---
    # Key functions: display, writeImage, imageData, numberOfFrames, colorMode, showIds
    display(img, method="raster")
    text(x = 20, y = 20, label = "Parrots", adj = c(0,1), col = "orange", cex = 2)
    dev.print(jpeg, filename = filename , width = dim(img)[1], height = dim(img)[2])

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ebimage_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ebimage_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ebimage_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_EBIMAGE:", paste0("    ebimage: ", packageVersion("EBImage"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ebimage_results.csv
    touch ${prefix}_ebimage_output.rds
    echo "BIOC_EBIMAGE:" > versions.yml
    echo "    ebimage: 0.0.0" >> versions.yml
    """
}


workflow BIOC_EBIMAGE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_EBIMAGE(ch_input)

    emit:
    results  = BIOC_EBIMAGE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_EBIMAGE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_EBIMAGE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_EBIMAGE.out.versions  // channel: path(versions.yml)
}
