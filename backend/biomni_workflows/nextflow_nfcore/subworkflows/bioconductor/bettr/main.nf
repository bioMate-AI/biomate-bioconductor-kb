#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: bettr
// bettr provides a set of interactive visualization methods to explore the results of a benchmarking s
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/bettr/inst/doc/bettr.R
// Upstream  : SummarizedExperiment, dplyr, tibble
// Downstream: none
//
// Install: BiocManager::install("bettr")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BETTR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-bettr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-bettr:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-bettr:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_bettr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_bettr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_bettr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(bettr)
    library(jsonlite)

    # --- Data Assembly [Data Assembly] ---
    # Key functions: assembleSE
    df <- data.frame(
        Method = c("M1", "M2", "M3"),
        metric1 = c(1, 2, 3),
        metric2 = c(3, 1, 2)
    )
    metricInfo <- data.frame(
        Metric = c("metric1", "metric2"),
        Group = c("G1", "G2")
    )
    idInfo <- data.frame(
        Method = c("M1", "M2", "M3"),
        Type = c("T1", "T1", "T2")
    )
    se <- assembleSE(
        df = df,
        idCol = "Method",
        metricInfo = metricInfo,
        idInfo = idInfo
    )

    # --- Advanced Assembly with Transformations [Data Assembly] ---
    # Key functions: assembleSE
    res <- read.csv(system.file("extdata", "duo2018_results.csv",
                                package = "bettr"))
    metricInfo <- data.frame(
        Metric = colnames(res)[-1],
        Class = sub("_.*", "", colnames(res)[-1])
    )
    initialTransforms <- lapply(
        res[, grep("elapsed|nclust", colnames(res), value = TRUE)],
        function(i) list(flip = TRUE, transform = '[0,1]')
    )
    duo2018 <- assembleSE(
        df = res,
        idCol = "method",
        metricInfo = metricInfo,
        initialTransforms = initialTransforms
    )

    # --- Data Preparation and Weighting [Data Preparation] ---
    # Key functions: bettrGetReady
    metadata(duo2018)$bettrInfo$initialWeights["Class_ARI"] <- 0.55
    prepData <- bettrGetReady(
        bettrSE = duo2018,
        idCol = "method",
        scoreMethod = "weighted mean",
        metricGrouping = "Class",
        metricCollapseGroup = TRUE
    )

    # --- Performance Visualization [Visualisation] ---
    # Key functions: makeHeatmap, makePolarPlot
    heatmap_plot <- makeHeatmap(bettrList = prepData)
    polar_plot <- makePolarPlot(bettrList = prepData)

    # --- Interactive Dashboard Setup [Visualisation] ---
    # Key functions: bettr
    app <- bettr(
        bettrSE = duo2018,
        bstheme = "sandstone"
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_bettr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_bettr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_bettr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BETTR:", paste0("    bettr: ", packageVersion("bettr"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bettr_results.csv
    touch ${prefix}_bettr_output.rds
    echo "BIOC_BETTR:" > versions.yml
    echo "    bettr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BETTR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BETTR(ch_input)

    emit:
    results  = BIOC_BETTR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BETTR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BETTR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BETTR.out.versions  // channel: path(versions.yml)
}
