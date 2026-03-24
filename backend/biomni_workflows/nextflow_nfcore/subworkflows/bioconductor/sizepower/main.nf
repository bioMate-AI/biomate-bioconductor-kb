#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: sizepower
// This package has been prepared to assist users in computing either a sample size or power value for 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/sizepower/inst/doc/sizepower.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("sizepower")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SIZEPOWER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-sizepower"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-sizepower:1.76.0--r44_0' :
        'quay.io/biocontainers/bioconductor-sizepower:1.76.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_sizepower_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_sizepower_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_sizepower_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(sizepower)
    library(jsonlite)

    # --- Randomized [] ---
    # Key functions: randomized
    sampleSize.randomized(ER0=1, G0=2000, power=0.9, absMu1=1, sigmad=0.566)
    # --- Matched [] ---
    # Key functions: matched
    sampleSize.matched(ER0=1, G0=2000, power=0.9, absMu1=1, sigmad=0.495)
    # --- Multi [] ---
    # Key functions: multi
    power.multi(ER0=1, G0=2000, numTrt=5, absMu1=1, sigma=0.4, n=6)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_sizepower_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_sizepower_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_sizepower_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SIZEPOWER:", paste0("    sizepower: ", packageVersion("sizepower"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sizepower_results.csv
    touch ${prefix}_sizepower_output.rds
    echo "BIOC_SIZEPOWER:" > versions.yml
    echo "    sizepower: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SIZEPOWER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SIZEPOWER(ch_input)

    emit:
    results  = BIOC_SIZEPOWER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SIZEPOWER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SIZEPOWER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SIZEPOWER.out.versions  // channel: path(versions.yml)
}
