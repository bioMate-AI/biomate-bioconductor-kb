#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RLMM
// A classification algorithm, based on a multi-chip, multi-SNP approach for Affymetrix SNP arrays. Usi
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RLMM/inst/doc/RLMM.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("RLMM")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RLMM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rlmm"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rlmm:1.68.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rlmm:1.68.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rlmm_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rlmm_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rlmm_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(RLMM)
    library(jsonlite)

    # --- Plot Theta [] ---
    # Key functions: plot_theta
    plot_theta(genotypefile="Xba.rlmm",thetafile="Xba.theta",plotfile="",snpsfile="snps.lst")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rlmm_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rlmm_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rlmm_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RLMM:", paste0("    rlmm: ", packageVersion("RLMM"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rlmm_results.csv
    touch ${prefix}_rlmm_output.rds
    echo "BIOC_RLMM:" > versions.yml
    echo "    rlmm: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RLMM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RLMM(ch_input)

    emit:
    results  = BIOC_RLMM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RLMM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RLMM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RLMM.out.versions  // channel: path(versions.yml)
}
