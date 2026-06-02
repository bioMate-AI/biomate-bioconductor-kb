#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CCPROMISE
// Perform Canonical correlation between two forms of high demensional genetic data, and associate the 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CCPROMISE/inst/doc/CCPROMISE.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("CCPROMISE")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CCPROMISE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ccpromise"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ccpromise:1.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ccpromise:1.32.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ccpromise_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ccpromise_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ccpromise_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CCPROMISE)
    library(PrbPROMISE)
    library(jsonlite)

    # --- Load Ccpromise Package And Data [] ---
    # Key functions: data
    library(CCPROMISE)
    data(exmplESet)
    data(exmplMSet)
    data(exmplGeneSet)
    data(exmplPat)
    # --- Ccpromise At Gene Level [] ---
    # Key functions: CCPROMISE

    # --- Promise At Probe Pair Level [] ---
    # Key functions: PrbPROMISE


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ccpromise_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ccpromise_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ccpromise_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CCPROMISE:", paste0("    ccpromise: ", packageVersion("CCPROMISE"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ccpromise_results.csv
    touch ${prefix}_ccpromise_output.rds
    echo "BIOC_CCPROMISE:" > versions.yml
    echo "    ccpromise: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CCPROMISE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CCPROMISE(ch_input)

    emit:
    results  = BIOC_CCPROMISE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CCPROMISE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CCPROMISE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CCPROMISE.out.versions  // channel: path(versions.yml)
}
