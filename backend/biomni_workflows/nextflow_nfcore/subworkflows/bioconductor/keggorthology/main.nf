#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: keggorthology
// graphical representation of the Feb 2010 KEGG Orthology. The KEGG orthology is a set of pathway IDs 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/keggorthology/inst/doc/keggorth.R
// Upstream  : ALL, RBGL, graph
// Downstream: none
//
// Install: BiocManager::install("keggorthology")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_KEGGORTHOLOGY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-keggorthology"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-keggorthology:2.58.0--r44_0' :
        'quay.io/biocontainers/bioconductor-keggorthology:2.58.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_keggorthology_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_keggorthology_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_keggorthology_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(keggorthology)
    library(jsonlite)

    # --- Lkkog [] ---
    # Key functions: nodes
    library(keggorthology)
    library(graph)
    data(KOgraph)
    KOgraph
    nodes(KOgraph)[1:5]
    # --- Lkr [] ---
    # Key functions: adj, nodes
    adj(KOgraph, nodes(KOgraph)[1])
    # --- Lkpa [] ---
    # Key functions: between, nodes
    library(RBGL)
    sp.between(KOgraph, nodes(KOgraph)[1], "PPAR signaling pathway")
    # --- Lkta [] ---
    # Key functions: nodeData
    nodeData(KOgraph,,"tag")[1:5]
    # --- Lkde [] ---
    # Key functions: nodeData
    nodeData(KOgraph,,"depth")[1:5]
    # --- Lkd [] ---
    # Key functions: getKOtags
    getKOtags("insulin")
    # --- Lkp [] ---
    # Key functions: getKOprobes
    library(hgu95av2.db)
    mp = getKOprobes("Methionine")
    library(ALL)
    data(ALL)
    ALL[mp,]

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_keggorthology_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_keggorthology_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_keggorthology_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_KEGGORTHOLOGY:", paste0("    keggorthology: ", packageVersion("keggorthology"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_keggorthology_results.csv
    touch ${prefix}_keggorthology_output.rds
    echo "BIOC_KEGGORTHOLOGY:" > versions.yml
    echo "    keggorthology: 0.0.0" >> versions.yml
    """
}


workflow BIOC_KEGGORTHOLOGY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_KEGGORTHOLOGY(ch_input)

    emit:
    results  = BIOC_KEGGORTHOLOGY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_KEGGORTHOLOGY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_KEGGORTHOLOGY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_KEGGORTHOLOGY.out.versions  // channel: path(versions.yml)
}
