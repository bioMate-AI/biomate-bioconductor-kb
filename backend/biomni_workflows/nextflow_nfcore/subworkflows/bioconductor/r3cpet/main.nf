#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: R3CPET
// The package provides a method to infer the set of proteins that are more probably to work together t
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/R3CPET/inst/doc/R3CPET.R
// Upstream  : GenomicRanges, igraph
// Downstream: none
//
// Install: BiocManager::install("R3CPET")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_R3CPET {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-r3cpet"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-r3cpet:1.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-r3cpet:1.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_r3cpet_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_r3cpet_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_r3cpet_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(R3CPET)
    library(ChiapetExperimentData)
    library(GenerateNetworks)
    library(InferNetworks)
    library(jsonlite)

    # --- Network Inference [] ---
    # Key functions: createIndexes, GenerateNetworks, topEdges, topNodes, networks
    x <- createIndexes(x)
    hlda_file <- system.file("example", "hlda.RData", package = "R3CPET")
    load(hlda_file)
    edges <- topEdges(hlda)
    nodes <- topNodes(hlda)
    hlda <- GenerateNetworks(hlda)
    nets <- networks(hlda)


    # --- Expression Annotation and Clustering [] ---
    # Key functions: annotateExpression, clusterInteractions, getRegionsIncluster
    hlda_file <- system.file("example", "hlda.RData", package = "R3CPET")
    load(hlda_file)
    data(RPKMS, package = "R3CPET")
    hlda <- annotateExpression(hlda, RPKMS)
    hlda <- clusterInteractions(hlda, method = "sota", nbClus = 6)
    regions <- getRegionsIncluster(hlda, x, cluster = 3)


    # --- Result Visualization [] ---
    # Key functions: plot3CPETRes, visualizeCircos
    hlda_file <- system.file("example", "hlda.RData", package = "R3CPET")
    load(hlda_file)
    hlda <- GenerateNetworks(hlda)
    plot3CPETRes(hlda, type = "heatmap")
    plot3CPETRes(hlda, type = "curve")
    plot3CPETRes(hlda, type = "avgCurve")
    plot3CPETRes(hlda, type = "netSim")
    visualizeCircos(hlda, x, cluster = 4)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_r3cpet_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_r3cpet_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_r3cpet_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_R3CPET:", paste0("    r3cpet: ", packageVersion("R3CPET"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_r3cpet_results.csv
    touch ${prefix}_r3cpet_output.rds
    echo "BIOC_R3CPET:" > versions.yml
    echo "    r3cpet: 0.0.0" >> versions.yml
    """
}


workflow BIOC_R3CPET_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_R3CPET(ch_input)

    emit:
    results  = BIOC_R3CPET.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_R3CPET.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_R3CPET.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_R3CPET.out.versions  // channel: path(versions.yml)
}
