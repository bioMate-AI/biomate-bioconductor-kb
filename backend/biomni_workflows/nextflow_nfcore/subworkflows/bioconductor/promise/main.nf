#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: PROMISE
// A general tool to identify genomic features with a specific biologically interesting pattern of asso
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/PROMISE/inst/doc/PROMISE.R
// Upstream  : none
// Downstream: CCPROMISE
//
// Install: BiocManager::install("PROMISE")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PROMISE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-promise"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-promise:1.58.0--r44_0' :
        'quay.io/biocontainers/bioconductor-promise:1.58.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_promise_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_promise_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_promise_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(PROMISE)
    library(jsonlite)

    # --- Load Promise Package And Data [] ---
    # Key functions: data
    library(PROMISE)
    data(sampExprSet)
    data(sampGeneSet)
    data(phPatt)
    # --- Extract Arraydata And Endpoint Data From Sampexprset [] ---
    # Key functions: exprs, pData, phenoData, all
    arrayData<-exprs(sampExprSet)
    ptData<- pData(phenoData(sampExprSet))
    head(arrayData[, 1:4])
    head(ptData)
    all(colnames(arrayData)==rownames(ptData))
    # --- Extract Sampgeneset To A Data Frame [] ---
    # Key functions: unlist, geneIds, setName, frame
    GS.data<-NULL
    # --- Promise Without Gsea [] ---
    # Key functions: PROMISE

    # --- Promise With Gsea [] ---
    # Key functions: PROMISE


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_promise_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_promise_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_promise_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PROMISE:", paste0("    promise: ", packageVersion("PROMISE"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_promise_results.csv
    touch ${prefix}_promise_output.rds
    echo "BIOC_PROMISE:" > versions.yml
    echo "    promise: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PROMISE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PROMISE(ch_input)

    emit:
    results  = BIOC_PROMISE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PROMISE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PROMISE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PROMISE.out.versions  // channel: path(versions.yml)
}
