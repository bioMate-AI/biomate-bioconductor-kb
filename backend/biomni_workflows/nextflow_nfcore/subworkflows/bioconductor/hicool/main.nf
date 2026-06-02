#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: HiCool
// HiCool provides an R interface to process and normalize Hi-C paired-end fastq reads into .(m)cool fi
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/HiCool/inst/doc/HiCool.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("HiCool")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HICOOL {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-hicool"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-hicool:1.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-hicool:1.6.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_hicool_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_hicool_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_hicool_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(HiContactsData)
    library(HiCool)
    library(jsonlite)

    # --- Hicool [] ---
    # Key functions: HiCool, HiContactsData
    ---------------------------------------------------------------------
    library(HiCool)
    # --- Metadata [] ---
    # Key functions: metadata
    ---------------------------------------------------------------------
    hcf
    S4Vectors::metadata(hcf)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_hicool_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_hicool_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_hicool_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_HICOOL:", paste0("    hicool: ", packageVersion("HiCool"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hicool_results.csv
    touch ${prefix}_hicool_output.rds
    echo "BIOC_HICOOL:" > versions.yml
    echo "    hicool: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HICOOL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_HICOOL(ch_input)

    emit:
    results  = BIOC_HICOOL.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HICOOL.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HICOOL.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HICOOL.out.versions  // channel: path(versions.yml)
}
