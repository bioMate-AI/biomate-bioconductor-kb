#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BEAT
// Model-based analysis of single-cell methylation data
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BEAT/inst/doc/BEAT.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("BEAT")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BEAT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-beat"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-beat:1.44.0--r44_0' :
        'quay.io/biocontainers/bioconductor-beat:1.44.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_beat_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_beat_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_beat_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BEAT)
    library(jsonlite)

    # --- Showinput [] ---
    # Key functions: csv, path
    library(BEAT)
    localpath <- system.file('extdata', package = 'BEAT')
    positions <- read.csv(file.path(localpath, "sample.positions.csv"))
    head(positions)
    # --- Setconfig [] ---
    # Key functions: makeParams
    params <- makeParams(localpath, sampNames, convrates,
    is.reference, pminus = 0.2, regionSize = 10000, minCounts = 5)
    params
    # --- Doconvert [] ---
    # Key functions: positions_to_regions
    positions_to_regions(params)
    # --- Domodel [] ---
    # Key functions: generate_results
    generate_results(params)
    # --- Doepimutations [] ---
    # Key functions: epimutation_calls
    epiCalls <- epimutation_calls(params)
    head(epiCalls$methSites$singlecell,3)
    head(epiCalls$demethSites$singlecell,3)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_beat_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_beat_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_beat_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BEAT:", paste0("    beat: ", packageVersion("BEAT"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_beat_results.csv
    touch ${prefix}_beat_output.rds
    echo "BIOC_BEAT:" > versions.yml
    echo "    beat: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BEAT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BEAT(ch_input)

    emit:
    results  = BIOC_BEAT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BEAT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BEAT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BEAT.out.versions  // channel: path(versions.yml)
}
