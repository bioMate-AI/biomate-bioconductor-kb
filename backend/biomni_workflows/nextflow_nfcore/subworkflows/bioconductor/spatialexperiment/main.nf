#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SpatialExperiment
// Defines an S4 class for storing data from spatial -omics experiments. The class extends SingleCellEx
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SpatialExperiment/inst/doc/SpatialExperiment.R
// Upstream  : BumpyMatrix
// Downstream: alabaster.spatial, ExperimentSubset, imcRtools, SPIAT, tidySpatialExperiment
//
// Install: BiocManager::install("SpatialExperiment")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPATIALEXPERIMENT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-spatialexperiment"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-spatialexperiment:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-spatialexperiment:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_spatialexperiment_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_spatialexperiment_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_spatialexperiment_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SpatialExperiment)
    library(jsonlite)

    # --- Data Loading [] ---
    # Key functions: read10xVisium
    dir <- system.file(
        file.path("extdata", "10xVisium"),
        package = "SpatialExperiment"
    )
    sample_ids <- c("section1", "section2")
    samples <- file.path(dir, sample_ids, "outs")
    spe10x <- read10xVisium(
        samples = samples,
        sample_ids = sample_ids,
        type = "sparse",
        data = "raw",
        images = "lowres",
        load = FALSE
    )


    # --- Image Manipulation [] ---
    # Key functions: addImg, imgRaster, rmvImg
    spe <- addImg(
        spe,
        sample_id = "section1",
        image_id = "pomeranian",
        imageSource = "https://i.redd.it/3pw5uah7xo041.jpg",
        scaleFactor = NA_real_,
        load = TRUE
    )
    img <- imgRaster(spe, sample_id = "section1", image_id = "pomeranian")
    spe <- rmvImg(spe, "section1", "pomeranian")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_spatialexperiment_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_spatialexperiment_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_spatialexperiment_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SPATIALEXPERIMENT:", paste0("    spatialexperiment: ", packageVersion("SpatialExperiment"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spatialexperiment_results.csv
    touch ${prefix}_spatialexperiment_output.rds
    echo "BIOC_SPATIALEXPERIMENT:" > versions.yml
    echo "    spatialexperiment: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SPATIALEXPERIMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SPATIALEXPERIMENT(ch_input)

    emit:
    results  = BIOC_SPATIALEXPERIMENT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SPATIALEXPERIMENT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SPATIALEXPERIMENT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SPATIALEXPERIMENT.out.versions  // channel: path(versions.yml)
}
