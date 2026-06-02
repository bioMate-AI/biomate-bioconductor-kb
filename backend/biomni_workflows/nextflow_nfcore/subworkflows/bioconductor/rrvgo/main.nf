#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: rrvgo
// Reduce and visualize lists of Gene Ontology terms by identifying redudance based on semantic similar
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/rrvgo/inst/doc/rrvgo.R
// Upstream  : knitr
// Downstream: none
//
// Install: BiocManager::install("rrvgo")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RRVGO {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rrvgo"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rrvgo:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rrvgo:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rrvgo_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rrvgo_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rrvgo_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(rrvgo)
    library(jsonlite)

    # --- Redundant Term Reduction [] ---
    # Key functions: calculateSimMatrix, reduceSimMatrix
    go_analysis <- read.delim(
        system.file("extdata/example.txt", package="rrvgo")
    )
    simMatrix <- calculateSimMatrix(
        go_analysis$ID,
        orgdb="org.Hs.eg.db",
        ont="BP",
        method="Rel"
    )
    scores <- setNames(-log10(go_analysis$qvalue), go_analysis$ID)
    reducedTerms <- reduceSimMatrix(
        simMatrix,
        scores,
        threshold=0.7,
        orgdb="org.Hs.eg.db"
    )


    # --- Visualisation of Reduced Terms [] ---
    # Key functions: calculateSimMatrix, reduceSimMatrix, heatmapPlot, scatterPlot, wordcloudPlot
    go_analysis <- read.delim(
        system.file("extdata/example.txt", package="rrvgo")
    )
    simMatrix <- calculateSimMatrix(
        go_analysis$ID,
        orgdb="org.Hs.eg.db",
        ont="BP",
        method="Rel"
    )
    scores <- setNames(-log10(go_analysis$qvalue), go_analysis$ID)
    reducedTerms <- reduceSimMatrix(
        simMatrix,
        scores,
        threshold=0.7,
        orgdb="org.Hs.eg.db"
    )
    heatmapPlot(
        simMatrix, reducedTerms,
        annotateParent=TRUE, annotationLabel="parentTerm", fontsize=6
    )
    scatterPlot(simMatrix, reducedTerms)
    wordcloudPlot(reducedTerms, min.freq=1, colors="black")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rrvgo_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rrvgo_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rrvgo_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RRVGO:", paste0("    rrvgo: ", packageVersion("rrvgo"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rrvgo_results.csv
    touch ${prefix}_rrvgo_output.rds
    echo "BIOC_RRVGO:" > versions.yml
    echo "    rrvgo: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RRVGO_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RRVGO(ch_input)

    emit:
    results  = BIOC_RRVGO.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RRVGO.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RRVGO.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RRVGO.out.versions  // channel: path(versions.yml)
}
