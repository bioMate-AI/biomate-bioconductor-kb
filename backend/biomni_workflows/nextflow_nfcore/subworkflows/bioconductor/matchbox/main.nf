#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: matchBox
// The matchBox package enables comparing ranked vectors of features, merging multiple datasets, removi
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/matchBox/inst/doc/matchBox.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("matchBox")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MATCHBOX {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-matchbox"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-matchbox:1.48.0--r44_0' :
        'quay.io/biocontainers/bioconductor-matchbox:1.48.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_matchbox_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_matchbox_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_matchbox_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(matchBox)
    library(jsonlite)

    # --- Concordance Computation [] ---
    # Key functions: computeCat
    catDataRanks <- computeCat(
        data = mergedData,
        cols = c("study1.t", "study2.t"),
        idCol = "GeneID",
        method = "equalRank",
        decreasing = TRUE
    )


    # --- Concordance Visualisation [] ---
    # Key functions: plotCat
    plotCat(
        catData = catDataRanks,
        cex = 1.2,
        lwd = 1.2,
        cexPts = 1.2,
        spacePts = 30,
        col = "red",
        main = "CAT curves for decreasing t-statistics",
        where = "center",
        legend = TRUE,
        legCex = 1,
        ncol = 1,
        plotLayout = layout(matrix(1:2, ncol = 2), widths = c(2, 1))
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_matchbox_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_matchbox_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_matchbox_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MATCHBOX:", paste0("    matchbox: ", packageVersion("matchBox"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_matchbox_results.csv
    touch ${prefix}_matchbox_output.rds
    echo "BIOC_MATCHBOX:" > versions.yml
    echo "    matchbox: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MATCHBOX_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MATCHBOX(ch_input)

    emit:
    results  = BIOC_MATCHBOX.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MATCHBOX.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MATCHBOX.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MATCHBOX.out.versions  // channel: path(versions.yml)
}
