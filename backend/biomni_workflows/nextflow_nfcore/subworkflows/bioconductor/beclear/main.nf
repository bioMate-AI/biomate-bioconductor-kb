#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BEclear
// Provides functions to detect and correct for batch effects in DNA methylation data. The core functio
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BEclear/inst/doc/BEclear.R
// Upstream  : ids, pander
// Downstream: none
//
// Install: BiocManager::install("BEclear")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BECLEAR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-beclear"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-beclear:2.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-beclear:2.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_beclear_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_beclear_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_beclear_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BEclear)
    library(jsonlite)

    # --- kable [] ---
    # Key functions: kable
    data("BEclearData")
    knitr::kable(ex.data[1:10,1:5], caption = 'Some entries from the example data-set')
    knitr::kable(ex.samples[1:10,], caption = 'Some entries from the example sample annotation')
    # --- calc Batch Effects [] ---
    # Key functions: calcBatchEffects

    # --- calc Summary [] ---
    # Key functions: calcSummary
    summary <- calcSummary(medians = mdifs, pvalues = pvals)
    knitr::kable(head(summary), caption = 'Summary over the batch affected gene-sample combination of the example data set')
    # --- calc Score [] ---
    # Key functions: calcScore
    score <- calcScore(ex.data, ex.samples, summary, dir = getwd())
    knitr::kable(score, caption = 'Batch scores of the example data-set')
    # --- correct Batch Effect [] ---
    # Key functions: correctBatchEffect
    result <- correctBatchEffect(data = ex.data, samples = ex.samples)
    # --- make Boxplot [] ---
    # Key functions: makeBoxplot


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_beclear_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_beclear_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_beclear_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BECLEAR:", paste0("    beclear: ", packageVersion("BEclear"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_beclear_results.csv
    touch ${prefix}_beclear_output.rds
    echo "BIOC_BECLEAR:" > versions.yml
    echo "    beclear: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BECLEAR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BECLEAR(ch_input)

    emit:
    results  = BIOC_BECLEAR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BECLEAR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BECLEAR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BECLEAR.out.versions  // channel: path(versions.yml)
}
