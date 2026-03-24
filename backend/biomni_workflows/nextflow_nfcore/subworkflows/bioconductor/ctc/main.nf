#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ctc
// Tools for export and import classification trees and clusters to other programs
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ctc/inst/doc/ctc.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("ctc")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CTC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ctc"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ctc:1.80.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ctc:1.80.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ctc_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ctc_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ctc_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ctc)
    library(jsonlite)

    # --- Hierarchical clustering [] ---
    # Key functions: hclust, dist
    hr = hclust(dist(USArrests))
    hc = hclust(dist(t(USArrests)))
    # --- Heatmap analysis [] ---
    # Key functions: heatmap, r2xcluster, r2cluster, write, hc2Newick, r2atr, r2gtr, r2cdt
    r2atr(hc,file="cluster.atr")
    r2gtr(hr,file="cluster.gtr")
    r2cdt(hr,hc,USArrests ,file="cluster.cdt")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ctc_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ctc_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ctc_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CTC:", paste0("    ctc: ", packageVersion("ctc"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ctc_results.csv
    touch ${prefix}_ctc_output.rds
    echo "BIOC_CTC:" > versions.yml
    echo "    ctc: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CTC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CTC(ch_input)

    emit:
    results  = BIOC_CTC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CTC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CTC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CTC.out.versions  // channel: path(versions.yml)
}
