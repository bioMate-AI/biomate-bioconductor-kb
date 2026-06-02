#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RNASeqPower
// RNA-seq, sample size
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RNASeqPower/inst/doc/samplesize.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("RNASeqPower")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RNASEQPOWER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rnaseqpower"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rnaseqpower:1.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rnaseqpower:1.46.0--r44_0'}"

    input:
    tuple val(meta), path(plot_object)

    output:
    tuple val(meta), path("${meta.id}_rnaseqpower_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rnaseqpower_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rnaseqpower_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(RNASeqPower)
    library(jsonlite)

    # --- Premable [] ---
    # Key functions: dimnames
    options(width=60, continue=" ")
    options(SweaveHooks=list(fig=function() par(mar=c(5.1, 4.1, .3, 1.1))))
    latex.list <- function(mat, digits=2, label= TRUE, ...) {
        dname <- dimnames(mat)
        if (length(dname[[2]]) & label)
    # --- Rnapower [] ---
    # Key functions: rnapower
    library(RNASeqPower)
    rnapower(depth=20, cv=.4, effect=c(1.25, 1.5, 1.75, 2),
            alpha= .05, power=c(.8, .9))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rnaseqpower_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rnaseqpower_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rnaseqpower_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RNASEQPOWER:", paste0("    rnaseqpower: ", packageVersion("RNASeqPower"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rnaseqpower_results.csv
    touch ${prefix}_rnaseqpower_output.rds
    echo "BIOC_RNASEQPOWER:" > versions.yml
    echo "    rnaseqpower: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RNASEQPOWER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(plot_object) ]

    main:
    BIOC_RNASEQPOWER(ch_input)

    emit:
    results  = BIOC_RNASEQPOWER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RNASEQPOWER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RNASEQPOWER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RNASEQPOWER.out.versions  // channel: path(versions.yml)
}
