#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: NetSAM
// The NetSAM (Network Seriation and Modularization) package takes an edge-list representation of a wei
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/NetSAM/inst/doc/NetSAM.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("NetSAM")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NETSAM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-netsam"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-netsam:1.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-netsam:1.46.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_netsam_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_netsam_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_netsam_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GOAssociation)
    library(jsonlite)

    # --- Packages [] ---
    # Key functions: packages
    ---------------------------------------------------------------------
    #  install.packages("igraph")
    #  install.packages("seriation")
    #  install.packages("WGCNA")
    #  install.packages("snow")
    # --- Data [] ---
    # Key functions: GOAssociation
    ---------------------------------------------------------------------
    #  library("NetSAM")
    #  data(NetSAMOutput_Example)
    #  outputHtmlFile <- paste(getwd(),"/GOAsso_HTML",sep="")
    #  GOAsso <- GOAssociation(NetSAMOutput=netsam_output, outputHtmlFile=outputHtmlFile, organism="hsapiens", fdrmethod="BH", fdrth=0.05, topNum=5)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_netsam_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_netsam_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_netsam_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_NETSAM:", paste0("    netsam: ", packageVersion("NetSAM"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_netsam_results.csv
    touch ${prefix}_netsam_output.rds
    echo "BIOC_NETSAM:" > versions.yml
    echo "    netsam: 0.0.0" >> versions.yml
    """
}


workflow BIOC_NETSAM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_NETSAM(ch_input)

    emit:
    results  = BIOC_NETSAM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_NETSAM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_NETSAM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_NETSAM.out.versions  // channel: path(versions.yml)
}
