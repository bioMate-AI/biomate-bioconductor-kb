#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: findIPs
// Feature rankings can be distorted by a single case in the context of high-dimensional data. The case
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/findIPs/inst/doc/findIPs.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("findIPs")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FINDIPS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-findips"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-findips:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-findips:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_findips_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_findips_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_findips_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(findIPs)
    library(jsonlite)

    # --- Rank Summation [] ---
    # Key functions: sumRanks
    data(miller05, package = "findIPs")
    X <- miller05$X
    y <- miller05$y
    obj <- getdrop1ranks(X, y, fun = "t.test", decreasing = FALSE, topN = 100)
    results <- sumRanks(
        origRank = obj$origRank,
        drop1Rank = obj$drop1Rank,
        topN = 100,
        method = "adaptive"
    )


    # --- Informative Parameter Selection [] ---
    # Key functions: findIPs
    data(miller05, package = "findIPs")
    X <- miller05$X
    y <- miller05$y
    results.ipsr <- findIPs(
        X, 
        y, 
        fun = "t.test",
        decreasing = FALSE,
        method = "adaptive"
    )


    # --- Visualisation [] ---
    # Key functions: plotIPs, plotRankScatters, plotAdaptiveWeights
    data(miller05, package = "findIPs")
    X <- miller05$X
    y <- miller05$y
    results.ipsr <- findIPs(
        X, 
        y, 
        fun = "t.test",
        decreasing = FALSE,
        method = "adaptive"
    )
    plotIPs(results.ipsr, topn = 5, ylim = c(0, 8))
    plotRankScatters(results.ipsr)
    plotAdaptiveWeights(results.ipsr$kappa, n = 100, type = "line")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_findips_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_findips_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_findips_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FINDIPS:", paste0("    findips: ", packageVersion("findIPs"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_findips_results.csv
    touch ${prefix}_findips_output.rds
    echo "BIOC_FINDIPS:" > versions.yml
    echo "    findips: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FINDIPS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FINDIPS(ch_input)

    emit:
    results  = BIOC_FINDIPS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FINDIPS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FINDIPS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FINDIPS.out.versions  // channel: path(versions.yml)
}
