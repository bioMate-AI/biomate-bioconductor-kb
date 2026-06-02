#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: flowTime
// This package facilitates analysis of both timecourse and steady state flow cytometry experiments. Th
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/flowTime/inst/doc/gating-vignette.R
// Upstream  : BiocManager, dplyr, flowClust, flowCore, flowStats
// Downstream: none
//
// Install: BiocManager::install("flowTime")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FLOWTIME {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-flowtime"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-flowtime:1.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-flowtime:1.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_flowtime_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_flowtime_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_flowtime_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(flowTime)
    library(Subset)
    library(jsonlite)

    # --- Quantile Gating [] ---
    # Key functions: gate_quantile
    Debris <- gate_quantile(
        fr = data[[3]],
        channel = "FSC.A",
        probs = 0.99,
        filterId = "Debris"
    )
    filtered_data <- flowCore::filter(data[c(3, 21:24)], !Debris)


    # --- Flow Clustering Gating [] ---
    # Key functions: gate_flowClust_2d
    data.1frame <- data[[1]]
    flowCore::exprs(data.1frame) <- flowCore::fsApply(data, function(x) {
        flowCore::exprs(x)
    })
    yeast <- gate_flowClust_2d(
        data.1frame,
        xChannel = "FSC.A",
        yChannel = "SSC.A",
        K = 1,
        quantile = 0.95,
        min = c(0, 0)
    )


    # --- Singlet Gating [] ---
    # Key functions: gate_singlet
    singlets <- gate_singlet(
        x = flowCore::Subset(data.1frame, yeast),
        area = "FSC.A",
        height = "FSC.H",
        prediction_level = 0.999,
        maxit = 20
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_flowtime_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_flowtime_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_flowtime_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FLOWTIME:", paste0("    flowtime: ", packageVersion("flowTime"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_flowtime_results.csv
    touch ${prefix}_flowtime_output.rds
    echo "BIOC_FLOWTIME:" > versions.yml
    echo "    flowtime: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FLOWTIME_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FLOWTIME(ch_input)

    emit:
    results  = BIOC_FLOWTIME.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FLOWTIME.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FLOWTIME.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FLOWTIME.out.versions  // channel: path(versions.yml)
}
