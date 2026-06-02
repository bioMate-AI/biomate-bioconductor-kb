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

    # --- Prepare Metrics Data [] ---
    # Key functions: metrics, methods, frame
    ---------------------------------------------------------------------
    ## Data for two metrics (metric1, metric2) for three methods (M1, M2, M3)
    df <- data.frame(Method = c("M1", "M2", "M3"),
                     metric1 = c(1, 2, 3),
                     metric2 = c(3, 1, 2))
    # --- Assemble SummarizedExperiment [] ---
    # Key functions: assembleSE
    ---------------------------------------------------------------------
    se <- assembleSE(df = df, idCol = "Method", metricInfo = metricInfo,
                     idInfo = idInfo)
    se
    # --- Run Interactive App [] ---
    # Key functions: bettr
    ---------------------------------------------------------------------
    #  ## Alternative 1
    #  bettr(bettrSE = se)
    #
    #  ## Alternative 2
    # --- Csv [] ---
    # Key functions: csv, tibble
    ---------------------------------------------------------------------
    res <- read.csv(system.file("extdata", "duo2018_results.csv",
                                package = "bettr"))
    dim(res)
    tibble(res)
    # --- Tibble [] ---
    # Key functions: tibble, mutate
    ---------------------------------------------------------------------
    metricInfo <- tibble(Metric = colnames(res)[-1]) |>
        mutate(Class = sub("_.*", "", Metric))
    head(metricInfo)
    table(metricInfo$Class)
    # --- Assemble SummarizedExperiment [] ---
    # Key functions: assembleSE
    ---------------------------------------------------------------------
    duo2018 <- assembleSE(df = res, idCol = "method", metricInfo = metricInfo,
                          initialTransforms = initialTransforms,
                          metricColors = metricColors, idColors = idColors)
    duo2018
    # --- Tibble [] ---
    # Key functions: tibble, assay, colData, definitions, metadata
    ---------------------------------------------------------------------
    ## Display the whole performance table
    tibble(assay(duo2018, "values"))
    ## Showing the first metric, evaluated on all datasets
    head(colData(duo2018), 12)
    # --- Run Interactive App [] ---
    # Key functions: bettr
    ---------------------------------------------------------------------
    #  bettr(bettrSE = duo2018, bstheme = "sandstone")
    # --- Generate Programmatic Plots [] ---
    # Key functions: metadata, bettrGetReady, makeHeatmap, makePolarPlot
    ---------------------------------------------------------------------
    ## Assign a higher weight to one of the collapsed metric classes
    metadata(duo2018)$bettrInfo$initialWeights["Class_ARI"] <- 0.55
    prepData <- bettrGetReady(
        bettrSE = duo2018, idCol = "method",

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
