#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: rfPred
// Based on external numerous data files where rfPred scores are pre-calculated on all genomic position
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/rfPred/inst/doc/vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("rfPred")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RFPRED {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rfpred"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rfpred:1.44.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rfpred:1.44.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rfpred_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rfpred_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rfpred_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(rfPred)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    data(variant_list_Y)
    print(variant_list_Y)
    # --- Rfpred Scores [] ---
    # Key functions: rfPred_scores
    result=rfPred_scores(variant_list=variant_list_Y,
                         data=system.file("extdata/chrY_rfPred.txtz", package="rfPred"),
                         index=system.file("extdata/chrY_rfPred.txtz.tbi", package="rfPred"))
    print(result)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rfpred_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rfpred_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rfpred_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RFPRED:", paste0("    rfpred: ", packageVersion("rfPred"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rfpred_results.csv
    touch ${prefix}_rfpred_output.rds
    echo "BIOC_RFPRED:" > versions.yml
    echo "    rfpred: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RFPRED_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RFPRED(ch_input)

    emit:
    results  = BIOC_RFPRED.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RFPRED.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RFPRED.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RFPRED.out.versions  // channel: path(versions.yml)
}
