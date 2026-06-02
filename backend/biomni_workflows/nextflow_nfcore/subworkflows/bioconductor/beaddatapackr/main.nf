#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BeadDataPackR
// Provides functionality for the compression and decompression of raw bead-level data from the Illumin
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BeadDataPackR/inst/doc/BeadDataPackR.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("BeadDataPackR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BEADDATAPACKR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-beaddatapackr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-beaddatapackr:1.58.0--r44_0' :
        'quay.io/biocontainers/bioconductor-beaddatapackr:1.58.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_beaddatapackr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_beaddatapackr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_beaddatapackr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BeadDataPackR)
    library(jsonlite)

    # --- Bead Data Decompression [] ---
    # Key functions: decompressBeadData
    babFile <- file.path(tempdir(), "example.bab")
    decompressBeadData(
        beadDataFile = babFile,
        outputPath = tempdir()
    )


    # --- Read Compressed Bead Data [] ---
    # Key functions: readBeadData
    babFile <- file.path(tempdir(), "example.bab")
    beadData <- readBeadData(
        beadDataFile = babFile,
        columns = c("G", "GrnX", "GrnY")
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_beaddatapackr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_beaddatapackr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_beaddatapackr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BEADDATAPACKR:", paste0("    beaddatapackr: ", packageVersion("BeadDataPackR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_beaddatapackr_results.csv
    touch ${prefix}_beaddatapackr_output.rds
    echo "BIOC_BEADDATAPACKR:" > versions.yml
    echo "    beaddatapackr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BEADDATAPACKR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BEADDATAPACKR(ch_input)

    emit:
    results  = BIOC_BEADDATAPACKR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BEADDATAPACKR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BEADDATAPACKR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BEADDATAPACKR.out.versions  // channel: path(versions.yml)
}
