#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: rWikiPathways
// Use this package to interface with the WikiPathways API. It provides programmatic access to WikiPath
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/rWikiPathways/inst/doc/Overview.R
// Upstream  : BridgeDbR, pacman
// Downstream: none
//
// Install: BiocManager::install("rWikiPathways")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RWIKIPATHWAYS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rwikipathways"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rwikipathways:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rwikipathways:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rwikipathways_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rwikipathways_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rwikipathways_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(rWikiPathways)
    library(jsonlite)

    # --- Listorganisms [] ---
    # Key functions: listOrganisms
    ---------------------------------------------------------------------
    #      listOrganisms()
    # --- Listpathways [] ---
    # Key functions: listPathways
    ---------------------------------------------------------------------
    #      hs.pathways <- listPathways('Homo sapiens')
    #      hs.pathways
    # --- Findpathwaysbyxref [] ---
    # Key functions: findPathwaysByXref
    ---------------------------------------------------------------------
    #      tnf.pathways <- findPathwaysByXref('TNF','H')
    #      tnf.pathways
    # --- Getpathwayinfo [] ---
    # Key functions: getPathwayInfo
    ---------------------------------------------------------------------
    #      getPathwayInfo('WP554')
    # --- Getxreflist [] ---
    # Key functions: getXrefList
    ---------------------------------------------------------------------
    #      getXrefList('WP554','L')
    # --- Getpathway [] ---
    # Key functions: getPathway
    ---------------------------------------------------------------------
    #      gpml <- getPathway('WP554')
    # --- Downloadpathwayarchive [] ---
    # Key functions: downloadPathwayArchive
    ---------------------------------------------------------------------
    #      downloadPathwayArchive()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rwikipathways_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rwikipathways_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rwikipathways_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RWIKIPATHWAYS:", paste0("    rwikipathways: ", packageVersion("rWikiPathways"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rwikipathways_results.csv
    touch ${prefix}_rwikipathways_output.rds
    echo "BIOC_RWIKIPATHWAYS:" > versions.yml
    echo "    rwikipathways: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RWIKIPATHWAYS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RWIKIPATHWAYS(ch_input)

    emit:
    results  = BIOC_RWIKIPATHWAYS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RWIKIPATHWAYS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RWIKIPATHWAYS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RWIKIPATHWAYS.out.versions  // channel: path(versions.yml)
}
