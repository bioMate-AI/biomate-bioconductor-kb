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

    # --- Xyplot analysis [] ---
    # Key functions: xyplot, transformList, rectangleGate, filters, norm2Filter, curv2Filter, densityplot, parallel
    n2Filter <- norm2Filter("SSC-H", "FSC-H", scale=2, filterId="Lymphocytes")
    n2Filter.results <- filter(GvHD, n2Filter)
    xyplot(`SSC-H` ~ `FSC-H` | Visit, data=GvHD, filter=n2Filter.results)

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
