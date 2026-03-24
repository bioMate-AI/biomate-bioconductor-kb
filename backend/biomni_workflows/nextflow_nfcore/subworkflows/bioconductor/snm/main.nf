#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: snm
// SNM is a modeling strategy especially designed for normalizing high-throughput genomic data. The und
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/snm/inst/doc/snm.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("snm")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SNM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-snm"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-snm:1.54.0--r44_0' :
        'quay.io/biocontainers/bioconductor-snm:1.54.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_snm_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_snm_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_snm_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(snm)
    library(jsonlite)

    # --- single Channel [] ---
    # Key functions: singleChannel
    singleChannel <- sim.singleChannel(12345)
    str(singleChannel)
    # --- snm [] ---
    # Key functions: snm
    snm.obj1 <- snm(singleChannel$raw.data,
    				singleChannel$bio.var,
    				singleChannel$adj.var,
    			        singleChannel$int.var)
    # --- test [] ---
    # Key functions: test
    ks.test(snm.obj1$pval[singleChannel$true.nulls],"punif")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_snm_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_snm_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_snm_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SNM:", paste0("    snm: ", packageVersion("snm"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_snm_results.csv
    touch ${prefix}_snm_output.rds
    echo "BIOC_SNM:" > versions.yml
    echo "    snm: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SNM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SNM(ch_input)

    emit:
    results  = BIOC_SNM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SNM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SNM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SNM.out.versions  // channel: path(versions.yml)
}
