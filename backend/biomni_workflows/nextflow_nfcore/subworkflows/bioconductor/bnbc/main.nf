#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: bnbc
// Tools to normalize (several) Hi-C data from replicates.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/bnbc/inst/doc/bnbc.R
// Upstream  : HiCBricks
// Downstream: none
//
// Install: BiocManager::install("bnbc")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BNBC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-bnbc"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-bnbc:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-bnbc:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_bnbc_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_bnbc_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_bnbc_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ContactGroup)
    library(jsonlite)

    # --- Contact Group [] ---
    # Key functions: ContactGroup
    cgEx <- ContactGroup(rowData=rowData(cgEx),
    contacts=contacts(cgEx),
    colData=colData(cgEx))
    # --- data to bnbc [] ---
    # Key functions: ContactGroup

    # --- band [] ---
    # Key functions: band
    mat.1 <- contacts(cgEx)[[1]]
    b1 <- band(mat=mat.1, band.no=2)
    band(mat=mat.1, band.no=2) <- b1 + 1

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_bnbc_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_bnbc_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_bnbc_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BNBC:", paste0("    bnbc: ", packageVersion("bnbc"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bnbc_results.csv
    touch ${prefix}_bnbc_output.rds
    echo "BIOC_BNBC:" > versions.yml
    echo "    bnbc: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BNBC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BNBC(ch_input)

    emit:
    results  = BIOC_BNBC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BNBC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BNBC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BNBC.out.versions  // channel: path(versions.yml)
}
