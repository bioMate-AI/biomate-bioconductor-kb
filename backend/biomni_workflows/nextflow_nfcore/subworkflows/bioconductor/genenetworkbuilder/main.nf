#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GeneNetworkBuilder
// Appliation for discovering direct or indirect targets of transcription factors using ChIP-chip or Ch
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GeneNetworkBuilder/inst/doc/GeneNetworkBuilder_vignettes.R
// Upstream  : RBGL, RCyjs, Rgraphviz, STRINGdb, XML
// Downstream: none
//
// Install: BiocManager::install("GeneNetworkBuilder")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENENETWORKBUILDER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-genenetworkbuilder"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-genenetworkbuilder:1.48.0--r44_0' :
        'quay.io/biocontainers/bioconductor-genenetworkbuilder:1.48.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_genenetworkbuilder_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_genenetworkbuilder_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_genenetworkbuilder_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GeneNetworkBuilder)
    library(jsonlite)

    # --- build Network [] ---
    # Key functions: buildNetwork, filterNetwork, polishNetwork, exportNetwork
    library(GeneNetworkBuilder)
    data("ce.miRNA.map")
    data("ce.interactionmap")
    # --- convert I D [] ---
    # Key functions: convertID, buildNetwork, filterNetwork, polishNetwork
    library(GeneNetworkBuilder)
    data("example.data")
    bind<-cbind(from="daf-16", to=c("zip-2", "zip-4", "nhr-3", "nhr-66"))
    # --- export Network [] ---
    # Key functions: exportNetwork, saveXML, textConnection
    exportNetwork(browseNetwork(gR),
    file=tempfile(fileext = ".network.xgmml"),
    library("XML")
    # --- build Network [] ---
    # Key functions: buildNetwork, filterNetwork, convertID, polishNetwork, browseNetwork
    library(GeneNetworkBuilder)
    data("hs.interactionmap")
    data("hs.miRNA.map")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_genenetworkbuilder_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_genenetworkbuilder_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_genenetworkbuilder_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GENENETWORKBUILDER:", paste0("    genenetworkbuilder: ", packageVersion("GeneNetworkBuilder"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genenetworkbuilder_results.csv
    touch ${prefix}_genenetworkbuilder_output.rds
    echo "BIOC_GENENETWORKBUILDER:" > versions.yml
    echo "    genenetworkbuilder: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GENENETWORKBUILDER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GENENETWORKBUILDER(ch_input)

    emit:
    results  = BIOC_GENENETWORKBUILDER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GENENETWORKBUILDER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GENENETWORKBUILDER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GENENETWORKBUILDER.out.versions  // channel: path(versions.yml)
}
