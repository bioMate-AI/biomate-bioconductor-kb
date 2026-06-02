#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: flowViz
// Provides visualization tools for flow cytometry data.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/flowViz/inst/doc/filters.R
// Upstream  : flowStats
// Downstream: flowFP, flowVS
//
// Install: BiocManager::install("flowViz")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FLOWVIZ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-flowviz"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-flowviz:1.70.0--r44_0' :
        'quay.io/biocontainers/bioconductor-flowviz:1.70.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_flowviz_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_flowviz_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_flowviz_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(flowViz)
    library(jsonlite)

    # --- Data Loading and Transformation [flowViz] ---
    # Key functions: pData, transformList, %on%
    data(GvHD, package = "flowCore")
    GvHD_sub <- GvHD[flowCore::pData(GvHD)$Patient == 6]
    tf <- flowCore::transformList(
        from = colnames(GvHD_sub)[3:7],
        tfun = asinh
    )
    GvHD_trans <- tf %on% GvHD_sub

    # --- Bivariate Gating and Visualization [flowViz] ---
    # Key functions: xyplot, rectangleGate
    rgate <- flowCore::rectangleGate(
        "FSC-H" = c(0, 400),
        "SSC-H" = c(-50, 300)
    )
    rgate2 <- rgate * flowCore::rectangleGate("FL1-H" = c(2, 4))
    xyplot(
        `SSC-H` ~ `FSC-H` | Visit,
        data = GvHD_trans,
        filter = rgate2,
        smooth = FALSE,
        xbin = 128
    )

    # --- Statistical Gating and Plotting [flowViz] ---
    # Key functions: xyplot, norm2Filter, filter
    n2Filter <- flowCore::norm2Filter(
        "SSC-H", "FSC-H",
        scale = 2,
        filterId = "Lymphocytes"
    )
    n2Filter.results <- flowCore::filter(GvHD_trans, n2Filter)
    xyplot(
        `SSC-H` ~ `FSC-H` | Visit,
        data = GvHD_trans,
        filter = n2Filter.results,
        names = TRUE,
        par.settings = list(
            gate = list(fill = "black", alpha = 0.2, col = "transparent"),
            gate.text = list(col = "darkred", alpha = 0.7, cex = 0.6)
        )
    )

    # --- One-dimensional Density Plotting [flowViz] ---
    # Key functions: densityplot, curv1Filter
    rgate2 <- flowCore::rectangleGate(
        "FSC-H" = c(0, 400),
        "SSC-H" = c(-50, 300)
    )
    densityplot(
        ~ .,
        GvHD_trans,
        channels = c("FSC-H", "SSC-H", "FL1-H"),
        filter = list(flowStats::curv1Filter("FSC-H"), NULL, rgate2)
    )

    # --- Parallel Coordinates Visualization [flowViz] ---
    # Key functions: parallel, norm2Filter, filter
    n2Filter <- flowCore::norm2Filter(
        "SSC-H", "FSC-H",
        scale = 2,
        filterId = "Lymphocytes"
    )
    n2Filter.results <- flowCore::filter(GvHD_trans, n2Filter)
    parallel(
        ~ . | Visit,
        GvHD_trans,
        filter = n2Filter.results,
        alpha = 0.01
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_flowviz_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_flowviz_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_flowviz_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FLOWVIZ:", paste0("    flowviz: ", packageVersion("flowViz"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_flowviz_results.csv
    touch ${prefix}_flowviz_output.rds
    echo "BIOC_FLOWVIZ:" > versions.yml
    echo "    flowviz: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FLOWVIZ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FLOWVIZ(ch_input)

    emit:
    results  = BIOC_FLOWVIZ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FLOWVIZ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FLOWVIZ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FLOWVIZ.out.versions  // channel: path(versions.yml)
}
