#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: UniProt.ws
// The Universal Protein Resource (UniProt) is a comprehensive resource for protein sequence and annota
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/UniProt.ws/inst/doc/UniProt.ws.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("UniProt.ws")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_UNIPROT_WS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-uniprot_ws"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-uniprot.ws:2.46.1--r44_0' :
        'quay.io/biocontainers/bioconductor-uniprot.ws:2.46.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_uniprot_ws_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_uniprot_ws_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_uniprot_ws_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(UniProt.ws)
    library(jsonlite)

    # --- available Uniprot Species [] ---
    # Key functions: availableUniprotSpecies
    availableUniprotSpecies(pattern="musculus")
    # --- keys [] ---
    # Key functions: keys
    egs <- keys(up, "GeneID")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_uniprot_ws_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_uniprot_ws_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_uniprot_ws_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_UNIPROT_WS:", paste0("    uniprot_ws: ", packageVersion("UniProt.ws"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_uniprot_ws_results.csv
    touch ${prefix}_uniprot_ws_output.rds
    echo "BIOC_UNIPROT_WS:" > versions.yml
    echo "    uniprot_ws: 0.0.0" >> versions.yml
    """
}


workflow BIOC_UNIPROT_WS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_UNIPROT_WS(ch_input)

    emit:
    results  = BIOC_UNIPROT_WS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_UNIPROT_WS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_UNIPROT_WS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_UNIPROT_WS.out.versions  // channel: path(versions.yml)
}
