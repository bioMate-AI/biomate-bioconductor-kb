#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: mzID
// A parser for mzIdentML files implemented using the XML package. The parser tries to be general and a
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/mzID/inst/doc/HOWTO_mzID.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("mzID")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MZID {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mzid"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mzid:1.44.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mzid:1.44.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mzid_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mzid_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mzid_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(mzID)
    library(jsonlite)

    # --- mz I D [] ---
    # Key functions: mzID

    # --- flatten [] ---
    # Key functions: flatten
    flatResults <- flatten(mzResults)
    names(flatResults)
    nrow(flatResults)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mzid_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mzid_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mzid_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MZID:", paste0("    mzid: ", packageVersion("mzID"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mzid_results.csv
    touch ${prefix}_mzid_output.rds
    echo "BIOC_MZID:" > versions.yml
    echo "    mzid: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MZID_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MZID(ch_input)

    emit:
    results  = BIOC_MZID.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MZID.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MZID.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MZID.out.versions  // channel: path(versions.yml)
}
