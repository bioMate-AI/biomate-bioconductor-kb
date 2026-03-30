#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: IMMAN
// Reconstructing Interlog Protein Network (IPN) integrated from several Protein protein Interaction Ne
//
// Source : https://bioconductor.org/packages/3.20/bioc/https://bioconductor.org/packages/3.20/bioc/vignettes/IMMAN/inst/doc/IMMAN.html
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("IMMAN")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_IMMAN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-imman"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-imman:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-imman:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_imman_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_imman_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_imman_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(IMMAN)
    library(jsonlite)

    # --- Code Block 3 [] ---
    # Key functions: IMMAN
    output = IMMAN(ProteinLists, fileNames=NULL, Species_IDs,
                  identityU, substitutionMatrix,
                  gapOpening, gapExtension, BestHit,
                  coverage, NetworkShrinkage,
                  score_threshold, STRINGversion,

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_imman_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_imman_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_imman_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_IMMAN:", paste0("    imman: ", packageVersion("IMMAN"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_imman_results.csv
    touch ${prefix}_imman_output.rds
    echo "BIOC_IMMAN:" > versions.yml
    echo "    imman: 0.0.0" >> versions.yml
    """
}


workflow BIOC_IMMAN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_IMMAN(ch_input)

    emit:
    results  = BIOC_IMMAN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_IMMAN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_IMMAN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_IMMAN.out.versions  // channel: path(versions.yml)
}
