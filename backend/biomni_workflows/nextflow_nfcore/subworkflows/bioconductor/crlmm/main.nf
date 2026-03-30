#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: crlmm
// Faster implementation of CRLMM specific to SNP 5.0 and 6.0 arrays, as well as a copy number tool spe
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/crlmm/inst/doc/genotyping.R
// Upstream  : hapmapsnp6, oligoClasses
// Downstream: MAGAR
//
// Install: BiocManager::install("crlmm")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CRLMM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-crlmm"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-crlmm:1.64.1--r44_0' :
        'quay.io/biocontainers/bioconductor-crlmm:1.64.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_crlmm_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_crlmm_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_crlmm_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(crlmm)
    library(jsonlite)

    # --- Crlmm [] ---
    # Key functions: celfiles, time, crlmm
    require(oligoClasses)
    library(crlmm)
    library(hapmapsnp6)
    path <- system.file("celFiles", package="hapmapsnp6")
    celFiles <- list.celfiles(path, full.names=TRUE)
    # --- Out [] ---
    # Key functions: calls, confs
    calls(crlmmResult)[1:10,]
    confs(crlmmResult)[1:10,]
    crlmmResult[["SNR"]]

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_crlmm_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_crlmm_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_crlmm_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CRLMM:", paste0("    crlmm: ", packageVersion("crlmm"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_crlmm_results.csv
    touch ${prefix}_crlmm_output.rds
    echo "BIOC_CRLMM:" > versions.yml
    echo "    crlmm: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CRLMM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CRLMM(ch_input)

    emit:
    results  = BIOC_CRLMM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CRLMM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CRLMM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CRLMM.out.versions  // channel: path(versions.yml)
}
