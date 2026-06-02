#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: arrayMvout
// This package supports the application of diverse quality metrics to AffyBatch instances, summarizing
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/arrayMvout/inst/doc/arrayMvout.R
// Upstream  : MAQCsubset, affyPLM, mdqc, mvoutData
// Downstream: none
//
// Install: BiocManager::install("arrayMvout")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ARRAYMVOUT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-arraymvout"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-arraymvout:1.64.0--r44_0' :
        'quay.io/biocontainers/bioconductor-arraymvout:1.64.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_arraymvout_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_arraymvout_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_arraymvout_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(arrayMvout)
    library(AffyRNAdeg)
    library(ArrayOutliers)
    library(NUSE)
    library(RLE)
    library(jsonlite)

    # --- Outlier Detection on QA Data [] ---
    # Key functions: ArrayOutliers
    res_itn <- arrayMvout::ArrayOutliers(
        itnQA,
        alpha = 0.05
    )


    # --- Outlier Visualization [] ---
    # Key functions: plot
    plot(res_itn, choices = c(1, 3))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_arraymvout_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_arraymvout_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_arraymvout_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ARRAYMVOUT:", paste0("    arraymvout: ", packageVersion("arrayMvout"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_arraymvout_results.csv
    touch ${prefix}_arraymvout_output.rds
    echo "BIOC_ARRAYMVOUT:" > versions.yml
    echo "    arraymvout: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ARRAYMVOUT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ARRAYMVOUT(ch_input)

    emit:
    results  = BIOC_ARRAYMVOUT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ARRAYMVOUT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ARRAYMVOUT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ARRAYMVOUT.out.versions  // channel: path(versions.yml)
}
