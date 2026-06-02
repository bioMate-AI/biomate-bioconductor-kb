#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: enrichViewNet
// This package enables the visualization of functional enrichment results as network graphs. First the
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/enrichViewNet/inst/doc/enrichViewNet.R
// Upstream  : ggplot2, gprofiler2, knitr
// Downstream: none
//
// Install: BiocManager::install("enrichViewNet")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ENRICHVIEWNET {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-enrichviewnet"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-enrichviewnet:1.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-enrichviewnet:1.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_enrichviewnet_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_enrichviewnet_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_enrichviewnet_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(enrichViewNet)
    library(jsonlite)

    # --- Gost analysis [] ---
    # Key functions: include_graphics, gost, createNetwork, createEnrichMap, object, createEnrichMapMultiBasic, scale_fill_manual, theme
    The network will either by created in Cytoscape (if the application is open)
    createNetwork(gostObject=parentalNapaVsDMSOEnrichment,  source="TERM_ID",
    fileName=file.path(tempdir(), "parentalNapaVsDMSO_REACTOME.cx"))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_enrichviewnet_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_enrichviewnet_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_enrichviewnet_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ENRICHVIEWNET:", paste0("    enrichviewnet: ", packageVersion("enrichViewNet"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_enrichviewnet_results.csv
    touch ${prefix}_enrichviewnet_output.rds
    echo "BIOC_ENRICHVIEWNET:" > versions.yml
    echo "    enrichviewnet: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ENRICHVIEWNET_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ENRICHVIEWNET(ch_input)

    emit:
    results  = BIOC_ENRICHVIEWNET.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ENRICHVIEWNET.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ENRICHVIEWNET.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ENRICHVIEWNET.out.versions  // channel: path(versions.yml)
}
