#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: copa
// COPA is a method to find genes that undergo recurrent fusion in a given cancer type by finding pairs
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/copa/inst/doc/copa.R
// Upstream  : colonCA
// Downstream: none
//
// Install: BiocManager::install("copa")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_COPA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-copa"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-copa:1.74.0--r44_0' :
        'quay.io/biocontainers/bioconductor-copa:1.74.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_copa_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_copa_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_copa_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(copa)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: pData
    library(copa)
    library(colonCA)
    data(colonCA)
    head(pData(colonCA), 10)
    # --- Copa [] ---
    # Key functions: copa, pData
    rslt <- copa(colonCA, as.numeric(pData(colonCA)[,3]))
    # --- Plotcopa [] ---
    # Key functions: plotCopa
    ## plotCopa(rslt, idx = 1, col = c("lightgreen","salmon"))
    # --- Summarycopa [] ---
    # Key functions: summaryCopa
    summaryCopa(rslt, 9)
    # --- Copaperm [] ---
    # Key functions: copaPerm
    prm <- copaPerm(colonCA, rslt, 9, 24)
    sum(prm >= 9)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_copa_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_copa_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_copa_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_COPA:", paste0("    copa: ", packageVersion("copa"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_copa_results.csv
    touch ${prefix}_copa_output.rds
    echo "BIOC_COPA:" > versions.yml
    echo "    copa: 0.0.0" >> versions.yml
    """
}


workflow BIOC_COPA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_COPA(ch_input)

    emit:
    results  = BIOC_COPA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_COPA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_COPA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_COPA.out.versions  // channel: path(versions.yml)
}
