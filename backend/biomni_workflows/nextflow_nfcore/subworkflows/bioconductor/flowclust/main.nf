#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: flowClust
// Robust model-based clustering using a t-mixture model with Box-Cox transformation. Note: users shoul
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/flowClust/inst/doc/flowClust.R
// Upstream  : flowCore, flowStats
// Downstream: none
//
// Install: BiocManager::install("flowClust")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FLOWCLUST {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-flowclust"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-flowclust:3.44.0--r44_0' :
        'quay.io/biocontainers/bioconductor-flowclust:3.44.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_flowclust_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_flowclust_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_flowclust_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(flowClust)
    library(jsonlite)

    # --- Outlier Identification [] ---
    # Key functions: ruleOutliers<-, summary
    ruleOutliers(res2[[2]]) <- list(level = 0.95)
    ruleOutliers(res2[[2]]) <- list(z.cutoff = 0.6)
    summary(res2[[2]])


    # --- Clustering Visualisation [] ---
    # Key functions: plot, density
    plot(res2[[2]], data = rituximab2, level = 0.8, z.cutoff = 0)
    res2.den <- density(res2[[2]], data = rituximab2)
    plot(res2.den, type = "image")


    # --- Gating and Subsetting [] ---
    # Key functions: tmixFilter, filter, Subset, split
    s2filter <- tmixFilter("s2filter", c("FL1.H", "FL3.H"), K = 3, B = 100)
    res2f <- filter(rituximab2, s2filter)
    subset_data <- Subset(rituximab2, res2f)
    split_data <- split(
        rituximab2,
        res2f,
        population = list(sc1 = 1:2, sc2 = 3)
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_flowclust_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_flowclust_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_flowclust_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FLOWCLUST:", paste0("    flowclust: ", packageVersion("flowClust"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_flowclust_results.csv
    touch ${prefix}_flowclust_output.rds
    echo "BIOC_FLOWCLUST:" > versions.yml
    echo "    flowclust: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FLOWCLUST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FLOWCLUST(ch_input)

    emit:
    results  = BIOC_FLOWCLUST.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FLOWCLUST.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FLOWCLUST.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FLOWCLUST.out.versions  // channel: path(versions.yml)
}
