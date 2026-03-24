#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: alabaster.spatial
// Save SpatialExperiment objects and their images into file artifacts, and load them back into memory.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/alabaster.spatial/inst/doc/userguide.R
// Upstream  : BiocStyle, SpatialExperiment
// Downstream: none
//
// Install: BiocManager::install("alabaster.spatial")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ALABASTER_SPATIAL {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-alabaster_spatial"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-alabaster.spatial:1.6.1--r44_0' :
        'quay.io/biocontainers/bioconductor-alabaster.spatial:1.6.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_alabaster_spatial_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_alabaster_spatial_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_alabaster_spatial_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(alabaster.spatial)
    library(jsonlite)

    # --- Readobject [] ---
    # Key functions: readObject, imgRaster, getImg
    ---------------------------------------------------------------------
    roundtrip <- readObject(tmp)
    plot(imgRaster(getImg(roundtrip, "section1")))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_alabaster_spatial_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_alabaster_spatial_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_alabaster_spatial_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ALABASTER_SPATIAL:", paste0("    alabaster_spatial: ", packageVersion("alabaster.spatial"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_alabaster_spatial_results.csv
    touch ${prefix}_alabaster_spatial_output.rds
    echo "BIOC_ALABASTER_SPATIAL:" > versions.yml
    echo "    alabaster_spatial: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ALABASTER_SPATIAL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ALABASTER_SPATIAL(ch_input)

    emit:
    results  = BIOC_ALABASTER_SPATIAL.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ALABASTER_SPATIAL.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ALABASTER_SPATIAL.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ALABASTER_SPATIAL.out.versions  // channel: path(versions.yml)
}
