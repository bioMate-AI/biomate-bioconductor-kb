#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Qtlizer
// This R package provides access to the Qtlizer web server. Qtlizer annotates lists of common small va
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Qtlizer/inst/doc/Qtlizer.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("Qtlizer")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_QTLIZER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-qtlizer"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-qtlizer:1.20.1--r44_0' :
        'quay.io/biocontainers/bioconductor-qtlizer:1.20.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_qtlizer_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_qtlizer_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_qtlizer_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Qtlizer)
    library(jsonlite)

    # --- Get Qtls [] ---
    # Key functions: get_qtls
    ---------------------------------------------------------------------
    # Call get_qtls with a variant as a single query term
    get_qtls("rs4284742")
    # --- Get Qtls [] ---
    # Key functions: get_qtls, comment
    ---------------------------------------------------------------------
    # View meta info
    df = get_qtls("rs4284742")
    comment(df)
    # --- Get Qtls [] ---
    # Key functions: get_qtls
    ---------------------------------------------------------------------
    # Return result as GRange object with ref_version hg38
    granges = get_qtls("rs4284742", return_obj = "granges", ref_version = "hg38")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_qtlizer_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_qtlizer_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_qtlizer_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_QTLIZER:", paste0("    qtlizer: ", packageVersion("Qtlizer"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_qtlizer_results.csv
    touch ${prefix}_qtlizer_output.rds
    echo "BIOC_QTLIZER:" > versions.yml
    echo "    qtlizer: 0.0.0" >> versions.yml
    """
}


workflow BIOC_QTLIZER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_QTLIZER(ch_input)

    emit:
    results  = BIOC_QTLIZER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_QTLIZER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_QTLIZER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_QTLIZER.out.versions  // channel: path(versions.yml)
}
