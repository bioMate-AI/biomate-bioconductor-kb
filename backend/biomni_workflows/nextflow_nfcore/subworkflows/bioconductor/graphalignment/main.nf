#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GraphAlignment
// Graph alignment is an extension package for the R programming environment which provides functions f
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GraphAlignment/inst/doc/GraphAlignment.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("GraphAlignment")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GRAPHALIGNMENT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-graphalignment"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-graphalignment:1.70.0--r44_0' :
        'quay.io/biocontainers/bioconductor-graphalignment:1.70.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_graphalignment_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_graphalignment_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_graphalignment_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GraphAlignment)
    library(AlignNetworks)
    library(AlignedPairs)
    library(AnalyzeAlignment)
    library(ComputeLinkParameters)
    library(ComputeNodeParameters)
    library(ComputeScores)
    library(GenerateExample)
    library(InitialAlignment)
    library(jsonlite)

    # --- Parameter Estimation [] ---
    # Key functions: ComputeLinkParameters, ComputeNodeParameters
    lookupLink <- seq(-2, 2, 0.5)
    lookupNode <- c(-0.5, 0.5, 1.5)
    linkParams <- ComputeLinkParameters(
        ex$a, ex$b, pinitial, lookupLink
    )
    nodeParams <- ComputeNodeParameters(
        dimA = 22, dimB = 22, ex$r,
        pinitial, lookupNode
    )


    # --- Network Alignment [] ---
    # Key functions: AlignNetworks
    al <- AlignNetworks(
        A = ex$a, B = ex$b, R = ex$r, P = pinitial,
        linkScore = linkParams$ls,
        selfLinkScore = linkParams$ls,
        nodeScore1 = nodeParams$s1, nodeScore0 = nodeParams$s0,
        lookupLink = lookupLink, lookupNode = lookupNode,
        bStart = 0.1, bEnd = 30,
        maxNumSteps = 50
    )


    # --- Alignment Evaluation [] ---
    # Key functions: ComputeScores, AnalyzeAlignment, AlignedPairs
    scores <- ComputeScores(
        A = ex$a, B = ex$b, R = ex$r, P = al,
        linkScore = linkParams$ls,
        selfLinkScore = linkParams$ls,
        nodeScore1 = nodeParams$s1, nodeScore0 = nodeParams$s0,
        lookupLink = lookupLink, lookupNode = lookupNode,
        symmetric = TRUE
    )
    analysis <- AnalyzeAlignment(
        A = ex$a, B = ex$b, R = ex$r, P = al,
        lookupNode = lookupNode, epsilon = 0.5
    )
    pairs <- AlignedPairs(ex$a, ex$b, al)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_graphalignment_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_graphalignment_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_graphalignment_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GRAPHALIGNMENT:", paste0("    graphalignment: ", packageVersion("GraphAlignment"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_graphalignment_results.csv
    touch ${prefix}_graphalignment_output.rds
    echo "BIOC_GRAPHALIGNMENT:" > versions.yml
    echo "    graphalignment: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GRAPHALIGNMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GRAPHALIGNMENT(ch_input)

    emit:
    results  = BIOC_GRAPHALIGNMENT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GRAPHALIGNMENT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GRAPHALIGNMENT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GRAPHALIGNMENT.out.versions  // channel: path(versions.yml)
}
