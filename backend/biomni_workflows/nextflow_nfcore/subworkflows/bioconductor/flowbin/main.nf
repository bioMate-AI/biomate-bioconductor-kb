#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: flowBin
// Software to combine flow cytometry data that has been multiplexed into multiple tubes with common ma
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/flowBin/inst/doc/flowBin.R
// Upstream  : flowFP
// Downstream: none
//
// Install: BiocManager::install("flowBin")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FLOWBIN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-flowbin"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-flowbin:1.42.0--r44_0' :
        'quay.io/biocontainers/bioconductor-flowbin:1.42.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_flowbin_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_flowbin_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_flowbin_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(flowBin)
    library(jsonlite)

    # --- Quantile Normalisation [] ---
    # Key functions: quantileNormalise, checkQNorm
    normed.sample <- quantileNormalise(aml.sample)
    qnorm.check <- checkQNorm(
        aml.sample,
        normed.sample,
        do.plot = FALSE
    )


    # --- Flow Binning [] ---
    # Key functions: flowBin
    tube.combined <- flowBin(
        tube.list = aml.sample@tube.set,
        bin.pars = aml.sample@bin.pars,
        control.tubes = aml.sample@control.tubes,
        expr.method = "medianFIDist",
        scale.expr = TRUE
    )


    # --- Heatmap Visualisation [] ---
    # Key functions: heatmap
    heatmap(tube.combined, scale = "none")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_flowbin_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_flowbin_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_flowbin_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FLOWBIN:", paste0("    flowbin: ", packageVersion("flowBin"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_flowbin_results.csv
    touch ${prefix}_flowbin_output.rds
    echo "BIOC_FLOWBIN:" > versions.yml
    echo "    flowbin: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FLOWBIN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FLOWBIN(ch_input)

    emit:
    results  = BIOC_FLOWBIN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FLOWBIN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FLOWBIN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FLOWBIN.out.versions  // channel: path(versions.yml)
}
