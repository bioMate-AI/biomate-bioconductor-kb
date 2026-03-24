#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DEGseq
// DEGseq is an R package to identify differentially expressed genes from RNA-Seq data.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DEGseq/inst/doc/DEGseq.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("DEGseq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DEGSEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-degseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-degseq:1.60.0--r44_0' :
        'quay.io/biocontainers/bioconductor-degseq:1.60.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_degseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_degseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_degseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DEGexp)
    library(jsonlite)

    # --- Layout [] ---
    # Key functions: DEGexp
    layout(matrix(c(1,2,3,4,5,6), 3, 2, byrow=TRUE))
    par(mar=c(2, 2, 2, 2))
    DEGexp(geneExpMatrix1=geneExpMatrix1, geneCol1=1, expCol1=c(2,3,4,5,6), groupLabel1="kidney",
           geneExpMatrix2=geneExpMatrix2, geneCol2=1, expCol2=c(2,3,4,5,6), groupLabel2="liver",
           method="MARS")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_degseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_degseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_degseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DEGSEQ:", paste0("    degseq: ", packageVersion("DEGseq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_degseq_results.csv
    touch ${prefix}_degseq_output.rds
    echo "BIOC_DEGSEQ:" > versions.yml
    echo "    degseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DEGSEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DEGSEQ(ch_input)

    emit:
    results  = BIOC_DEGSEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DEGSEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DEGSEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DEGSEQ.out.versions  // channel: path(versions.yml)
}
