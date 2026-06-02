#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CardinalIO
// Fast and efficient reading and writing of mass spectrometry imaging data files. Supports imzML and A
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CardinalIO/inst/doc/CardinalIO-guide.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("CardinalIO")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CARDINALIO {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cardinalio"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cardinalio:1.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cardinalio:1.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cardinalio_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cardinalio_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cardinalio_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ImzMeta)
    library(jsonlite)

    # --- example Imz M L File [] ---
    # Key functions: exampleImzMLFile, parseImzML
    path <- exampleImzMLFile("continuous")
    p <- parseImzML(path, ibd=TRUE)
    # --- tempfile [] ---
    # Key functions: tempfile, writeImzML
    path2 <- tempfile(fileext=".imzML")
    writeImzML(p, file=path2)
    # --- replicate [] ---
    # Key functions: replicate
    set.seed(2023)
    mz <- seq(500, 510, length.out=nmz)
    intensity <- replicate(nx * ny, rlnorm(nmz))
    # --- Imz Meta [] ---
    # Key functions: ImzMeta

    # --- tempfile [] ---
    # Key functions: tempfile, writeImzML
    path3 <- tempfile(fileext=".imzML")
    writeImzML(meta, file=path3, positions=positions, mz=mz, intensity=intensity)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cardinalio_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cardinalio_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cardinalio_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CARDINALIO:", paste0("    cardinalio: ", packageVersion("CardinalIO"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cardinalio_results.csv
    touch ${prefix}_cardinalio_output.rds
    echo "BIOC_CARDINALIO:" > versions.yml
    echo "    cardinalio: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CARDINALIO_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CARDINALIO(ch_input)

    emit:
    results  = BIOC_CARDINALIO.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CARDINALIO.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CARDINALIO.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CARDINALIO.out.versions  // channel: path(versions.yml)
}
