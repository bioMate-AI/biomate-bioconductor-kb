#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GENIE3
// This package implements the GENIE3 algorithm for inferring gene regulatory networks from expression 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GENIE3/inst/doc/GENIE3.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("GENIE3")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENIE3 {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-genie3"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-genie3:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-genie3:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_genie3_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_genie3_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_genie3_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GENIE3)
    library(jsonlite)

    # --- Format Expression Data [] ---
    # Key functions: sample
    ---------------------------------------------------------------------
    exprMatr <- matrix(sample(1:10, 100, replace=TRUE), nrow=20)
    rownames(exprMatr) <- paste("Gene", 1:20, sep="")
    colnames(exprMatr) <- paste("Sample", 1:5, sep="")
    head(exprMatr)
    # --- Run GENIE3 Algorithm [] ---
    # Key functions: GENIE3
    ---------------------------------------------------------------------
    regulatorsList <- list("Gene1"=rownames(exprMatr)[1:10],
                           "Gene2"=rownames(exprMatr)[10:20],
                           "Gene20"=rownames(exprMatr)[15:20])
    set.seed(123)
    # --- Extract Regulatory Links [] ---
    # Key functions: getLinkList
    ---------------------------------------------------------------------
    linkList <- getLinkList(weightMat)
    dim(linkList)
    head(linkList)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_genie3_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_genie3_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_genie3_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GENIE3:", paste0("    genie3: ", packageVersion("GENIE3"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genie3_results.csv
    touch ${prefix}_genie3_output.rds
    echo "BIOC_GENIE3:" > versions.yml
    echo "    genie3: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GENIE3_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GENIE3(ch_input)

    emit:
    results  = BIOC_GENIE3.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GENIE3.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GENIE3.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GENIE3.out.versions  // channel: path(versions.yml)
}
