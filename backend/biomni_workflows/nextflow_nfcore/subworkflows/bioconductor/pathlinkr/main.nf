#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: pathlinkR
// pathlinkR is an R package designed to facilitate analysis of RNA-Seq results. Specifically, our aim 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/pathlinkR/inst/doc/pathlinkR.R
// Upstream  : dplyr
// Downstream: none
//
// Install: BiocManager::install("pathlinkR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PATHLINKR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-pathlinkr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-pathlinkr:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-pathlinkr:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_pathlinkr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_pathlinkr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_pathlinkr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(pathlinkR)
    library(jsonlite)

    # --- Pathway Enrichment Analysis [] ---
    # Key functions: pathwayEnrichment, pathwayPlots
    data("exampleDESeqResults")
    enrichedResultsSigora <- pathwayEnrichment(
        inputList = exampleDESeqResults,
        analysis = "sigora",
        filterInput = TRUE,
        gpsRepo = "default"
    )
    pathwayPlots(
        pathwayEnrichmentResults = enrichedResultsSigora,
        columns = 2
    )


    # --- PPI Network Construction [] ---
    # Key functions: ppiBuildNetwork, ppiPlotNetwork
    data("exampleDESeqResults")
    exNetwork <- ppiBuildNetwork(
        rnaseqResult = exampleDESeqResults[[1]],
        filterInput = TRUE,
        order = "zero"
    )
    ppiPlotNetwork(
        network = exNetwork,
        title = names(exampleDESeqResults)[1],
        fillColumn = LogFoldChange,
        fillType = "foldChange",
        label = TRUE,
        labelColumn = hgncSymbol,
        legend = TRUE
    )


    # --- PPI Subnetwork Extraction [] ---
    # Key functions: ppiEnrichNetwork, ppiExtractSubnetwork, ppiPlotNetwork
    data("exampleDESeqResults")
    exNetwork <- ppiBuildNetwork(
        rnaseqResult = exampleDESeqResults[[1]],
        filterInput = TRUE,
        order = "zero"
    )
    exNetworkPathways <- ppiEnrichNetwork(
        network = exNetwork,
        analysis = "hallmark",
        filterResults = "default",
        geneUniverse = rownames(exampleDESeqResults[[1]])
    )
    exSubnetwork <- ppiExtractSubnetwork(
        network = exNetwork,
        pathwayEnrichmentResult = exNetworkPathways,
        pathwayToExtract = "INTERFERON GAMMA RESPONSE"
    )
    ppiPlotNetwork(
        network = exSubnetwork,
        fillType = "oneSided",
        fillColumn = degree,
        label = TRUE,
        labelColumn = hgncSymbol,
        legendTitle = "Degree"
    )


    # --- Pathway Network Analysis [] ---
    # Key functions: getPathwayDistances, pathnetFoundation, pathnetCreate, pathnetGGraph
    data("sigoraDatabase")
    data("exampleDESeqResults")
    pathwayDistancesJaccard <- getPathwayDistances(
        pathwayData = sigoraDatabase
    )
    startingPathways <- pathnetFoundation(
        mat = pathwayDistancesJaccard,
        maxDistance = 0.8
    )
    enrichedResultsSigora <- pathwayEnrichment(
        inputList = exampleDESeqResults,
        analysis = "sigora",
        filterInput = TRUE,
        gpsRepo = "default"
    )
    exPathwayNetworkInput <- enrichedResultsSigora[
        enrichedResultsSigora$comparison == "COVID Pos Over Time", 
    ]
    myPathwayNetwork <- pathnetCreate(
        pathwayEnrichmentResult = exPathwayNetworkInput,
        foundation = startingPathways
    )
    pathnetGGraph(
        myPathwayNetwork,
        labelProp = 0.1,
        nodeLabelSize = 3,
        nodeLabelOverlaps = 8,
        segColour = "red",
        themeBaseSize = 12
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_pathlinkr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_pathlinkr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_pathlinkr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PATHLINKR:", paste0("    pathlinkr: ", packageVersion("pathlinkR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pathlinkr_results.csv
    touch ${prefix}_pathlinkr_output.rds
    echo "BIOC_PATHLINKR:" > versions.yml
    echo "    pathlinkr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PATHLINKR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PATHLINKR(ch_input)

    emit:
    results  = BIOC_PATHLINKR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PATHLINKR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PATHLINKR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PATHLINKR.out.versions  // channel: path(versions.yml)
}
