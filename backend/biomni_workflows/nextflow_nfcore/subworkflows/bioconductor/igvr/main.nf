#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: igvR
// Access to igv.js, the Integrative Genomics Viewer running in a web browser.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/igvR/inst/doc/v00.basicIntro.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("igvR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_IGVR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-igvr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-igvr:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-igvr:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_igvr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_igvr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_igvr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(igvR)
    library(DataFrameAnnotationTrack)
    library(DataFrameQuantitativeTrack)
    library(jsonlite)

    # --- Genomic Region Navigation [] ---
    # Key functions: showGenomicRegion
    showGenomicRegion(
        obj = igv,
        region = "chr1:10,000,000-11,000,000"
    )


    # --- Track Creation and Display [] ---
    # Key functions: DataFrameQuantitativeTrack, displayTrack
    track <- DataFrameQuantitativeTrack(
        trackName = "Sample Quantitative Track",
        quantitativeData = track_data_frame,
        color = "blue"
    )
    displayTrack(igv, track)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_igvr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_igvr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_igvr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_IGVR:", paste0("    igvr: ", packageVersion("igvR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_igvr_results.csv
    touch ${prefix}_igvr_output.rds
    echo "BIOC_IGVR:" > versions.yml
    echo "    igvr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_IGVR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_IGVR(ch_input)

    emit:
    results  = BIOC_IGVR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_IGVR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_IGVR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_IGVR.out.versions  // channel: path(versions.yml)
}
