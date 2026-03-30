#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: LBE
// LBE is an efficient procedure for estimating the proportion of true null hypotheses, the false disco
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/LBE/inst/doc/LBE.R
// Upstream  : qvalue
// Downstream: none
//
// Install: BiocManager::install("LBE")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_LBE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-lbe"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-lbe:1.74.0--r44_0' :
        'quay.io/biocontainers/bioconductor-lbe:1.74.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_lbe_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_lbe_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_lbe_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(LBE)
    library(LBEa)
    library(LBEplot)
    library(LBEsummary)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    library(LBE)
    data(golub.pval)
    # --- Lbe [] ---
    # Key functions: LBE
    LBE.res <- LBE(golub.pval)
    # --- Lbeplot [] ---
    # Key functions: LBEplot
    LBEplot(LBE.res,plot.type="multiple")
    # --- Lbea [] ---
    # Key functions: LBEa
    LBEa(length(golub.pval),l=0.1)
    # --- Qvalue [] ---
    # Key functions: qvalue, LBEsummary
    library(qvalue)
    qvalue.res <- qvalue(golub.pval)
    summary(qvalue.res)
    LBEsummary(LBE.res)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_lbe_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_lbe_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_lbe_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_LBE:", paste0("    lbe: ", packageVersion("LBE"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_lbe_results.csv
    touch ${prefix}_lbe_output.rds
    echo "BIOC_LBE:" > versions.yml
    echo "    lbe: 0.0.0" >> versions.yml
    """
}


workflow BIOC_LBE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_LBE(ch_input)

    emit:
    results  = BIOC_LBE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_LBE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_LBE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_LBE.out.versions  // channel: path(versions.yml)
}
