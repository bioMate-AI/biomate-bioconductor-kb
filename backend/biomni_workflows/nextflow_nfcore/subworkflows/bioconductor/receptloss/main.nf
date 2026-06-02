#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: receptLoss
// receptLoss identifies genes whose expression is lost in subsets of tumors relative to normal tissue.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/receptLoss/inst/doc/receptLoss.R
// Upstream  : dplyr, ggplot2
// Downstream: none
//
// Install: BiocManager::install("receptLoss")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RECEPTLOSS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-receptloss"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-receptloss:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-receptloss:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_receptloss_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_receptloss_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_receptloss_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(receptLoss)
    library(jsonlite)


    # --- Warning=false [] ---
    # Key functions: rnorm
    library(receptLoss)
    library(dplyr)
    library(ggplot2)

    set.seed(100)

    ## Simulate matrix of expression values from
    ## 10 genes measured in both normal tissue and 
    ## tumor tissue in 100 patients

    exprMatrNml <- matrix(abs(rnorm(100, mean=2.5)), nrow=10) 
    exprMatrTum <- matrix(abs(rnorm(1000)), nrow=10)
    geneNames <- paste0(letters[seq_len(nrow(exprMatrNml))], 
                    seq_len(nrow(exprMatrNml)))
    rownames(exprMatrNml) <- rownames(exprMatrTum) <- geneNames

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_receptloss_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_receptloss_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_receptloss_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RECEPTLOSS:", paste0("    receptloss: ", packageVersion("receptLoss"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_receptloss_results.csv
    touch ${prefix}_receptloss_output.rds
    echo "BIOC_RECEPTLOSS:" > versions.yml
    echo "    receptloss: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RECEPTLOSS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RECEPTLOSS(ch_input)

    emit:
    results  = BIOC_RECEPTLOSS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RECEPTLOSS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RECEPTLOSS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RECEPTLOSS.out.versions  // channel: path(versions.yml)
}
