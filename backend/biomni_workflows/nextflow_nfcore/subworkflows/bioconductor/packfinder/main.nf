#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: packFinder
// Algorithm and tools for in silico pack-TYPE transposon discovery. Filters a given genome for propert
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/packFinder/inst/doc/packFinder.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("packFinder")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PACKFINDER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-packfinder"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-packfinder:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-packfinder:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_packfinder_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_packfinder_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_packfinder_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DNAString)
    library(DNAStringSet)
    library(jsonlite)

    # --- DNAString analysis [] ---
    # Key functions: DNAString, DNAStringSet, readDNAStringSet, packSearch, packClust, readUc, readBlast, tirClust
    packsToCsv(packMatches, "tempOutput/packMatches.csv")
    print(getPacksFromCsv("tempOutput/packMatches.csv"))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_packfinder_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_packfinder_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_packfinder_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PACKFINDER:", paste0("    packfinder: ", packageVersion("packFinder"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_packfinder_results.csv
    touch ${prefix}_packfinder_output.rds
    echo "BIOC_PACKFINDER:" > versions.yml
    echo "    packfinder: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PACKFINDER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PACKFINDER(ch_input)

    emit:
    results  = BIOC_PACKFINDER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PACKFINDER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PACKFINDER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PACKFINDER.out.versions  // channel: path(versions.yml)
}
