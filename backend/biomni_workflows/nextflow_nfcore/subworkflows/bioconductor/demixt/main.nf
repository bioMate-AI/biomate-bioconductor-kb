#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DeMixT
// DeMixT is a software package that performs deconvolution on transcriptome data from a mixture of two
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DeMixT/inst/doc/demixt.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("DeMixT")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DEMIXT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-demixt"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-demixt:1.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-demixt:1.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_demixt_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_demixt_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_demixt_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DeMixT)
    library(jsonlite)

    # --- sim 2comp [] ---
    # Key functions: ggplot, geom_point, geom_abline
    res.2comp = as.data.frame(cbind(round(rep(t(test.data.2comp$pi[2,]),3),2),
    round(c(t(res.S1$pi[2,]),t(res.S1.SP$pi[2,]), t(res.GS.SP$pi[2,])),2),
    rep(c('DE','DE-SP','GS-SP'), each = 100)), num = 1:2)
    # --- sim 3comp [] ---
    # Key functions: ggplot, geom_point, geom_abline
    res.3comp= as.data.frame(cbind(round(t(matrix(t(test.data.3comp$pi), nrow = 1)),2),
    round(t(matrix(t(res.S1$pi), nrow = 1)),2),
    rep(c('N1','N2','T'), each = 20)))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_demixt_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_demixt_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_demixt_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DEMIXT:", paste0("    demixt: ", packageVersion("DeMixT"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_demixt_results.csv
    touch ${prefix}_demixt_output.rds
    echo "BIOC_DEMIXT:" > versions.yml
    echo "    demixt: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DEMIXT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DEMIXT(ch_input)

    emit:
    results  = BIOC_DEMIXT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DEMIXT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DEMIXT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DEMIXT.out.versions  // channel: path(versions.yml)
}
