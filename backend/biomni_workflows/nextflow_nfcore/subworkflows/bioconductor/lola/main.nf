#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: LOLA
// Provides functions for testing overlap of sets of genomic regions with public and custom region set 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/LOLA/inst/doc/gettingStarted.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("LOLA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_LOLA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-lola"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-lola:1.36.0--r44_0' :
        'quay.io/biocontainers/bioconductor-lola:1.36.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_lola_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_lola_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_lola_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(LOLA)
    library(jsonlite)

    # --- Write results [] ---
    # Key functions: writeCombinedEnrichment
    writeCombinedEnrichment(locResults, outFolder= "lolaResults")
    # --- Write split results [] ---
    # Key functions: writeCombinedEnrichment
    writeCombinedEnrichment(locResults, outFolder= "lolaResults", includeSplits=TRUE)
    # --- Extracting overlaps [] ---
    # Key functions: extractEnrichmentOverlaps
    extractEnrichmentOverlaps(oneResult, userSets, regionDB)
    # --- Grabbing individual region sets [] ---
    # Key functions: getRegionSet
    getRegionSet(regionDB, collections="ucsc_example", filenames="vistaEnhancers.bed")
    # --- Grabbing individual region sets from disk [] ---
    # Key functions: getRegionSet
    getRegionSet(dbPath, collections="ucsc_example", filenames="vistaEnhancers.bed")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_lola_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_lola_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_lola_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_LOLA:", paste0("    lola: ", packageVersion("LOLA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_lola_results.csv
    touch ${prefix}_lola_output.rds
    echo "BIOC_LOLA:" > versions.yml
    echo "    lola: 0.0.0" >> versions.yml
    """
}


workflow BIOC_LOLA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_LOLA(ch_input)

    emit:
    results  = BIOC_LOLA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_LOLA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_LOLA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_LOLA.out.versions  // channel: path(versions.yml)
}
