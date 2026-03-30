#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BridgeDbR
// Use BridgeDb functions and load identifier mapping databases in R. It uses GitHub, Zenodo, and Figsh
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BridgeDbR/inst/doc/tutorial.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("BridgeDbR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BRIDGEDBR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-bridgedbr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-bridgedbr:2.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-bridgedbr:2.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_bridgedbr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_bridgedbr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_bridgedbr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BridgeDbR)
    library(jsonlite)

    # --- Getorganismcode [] ---
    # Key functions: getOrganismCode
    ---------------------------------------------------------------------
    code <- getOrganismCode("Rattus norvegicus")
    code
    # --- Getfullname [] ---
    # Key functions: getFullName, getSystemCode
    ---------------------------------------------------------------------
    fullName <- getFullName("Ce")
    fullName
    code <- getSystemCode("ChEBI")
    code
    # --- Getmatchingsources [] ---
    # Key functions: getMatchingSources
    ---------------------------------------------------------------------
    getMatchingSources("HMDB00555")
    getMatchingSources("ENSG00000100030")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_bridgedbr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_bridgedbr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_bridgedbr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BRIDGEDBR:", paste0("    bridgedbr: ", packageVersion("BridgeDbR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bridgedbr_results.csv
    touch ${prefix}_bridgedbr_output.rds
    echo "BIOC_BRIDGEDBR:" > versions.yml
    echo "    bridgedbr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BRIDGEDBR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BRIDGEDBR(ch_input)

    emit:
    results  = BIOC_BRIDGEDBR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BRIDGEDBR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BRIDGEDBR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BRIDGEDBR.out.versions  // channel: path(versions.yml)
}
