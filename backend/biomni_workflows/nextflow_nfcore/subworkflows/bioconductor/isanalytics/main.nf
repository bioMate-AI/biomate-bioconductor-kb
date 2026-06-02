#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ISAnalytics
// In gene therapy, stem cells are modified using viral vectors to deliver the therapeutic transgene an
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ISAnalytics/inst/doc/ISAnalytics.R
// Upstream  : BiocStyle, DT, RefManageR, devtools, sessioninfo
// Downstream: none
//
// Install: BiocManager::install("ISAnalytics")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ISANALYTICS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-isanalytics"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-isanalytics:1.16.1--r44_0' :
        'quay.io/biocontainers/bioconductor-isanalytics:1.16.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_isanalytics_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_isanalytics_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_isanalytics_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(PrintBibliography)
    library(jsonlite)

    # --- path [] ---
    # Key functions: path
    library("RefManageR")
    # --- tribble [] ---
    # Key functions: tribble, set_af_columns_def, set_mandatory_IS_vars, tempdir, unzip
    options("ISAnalytics.reports" = FALSE)
    options("ISAnalytics.reports" = TRUE)
    library(ISAnalytics)
    # --- Print Bibliography [] ---
    # Key functions: PrintBibliography
    PrintBibliography(bib, .opts = list(hyperlink = "to.doc", style = "html"))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_isanalytics_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_isanalytics_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_isanalytics_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ISANALYTICS:", paste0("    isanalytics: ", packageVersion("ISAnalytics"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_isanalytics_results.csv
    touch ${prefix}_isanalytics_output.rds
    echo "BIOC_ISANALYTICS:" > versions.yml
    echo "    isanalytics: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ISANALYTICS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ISANALYTICS(ch_input)

    emit:
    results  = BIOC_ISANALYTICS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ISANALYTICS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ISANALYTICS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ISANALYTICS.out.versions  // channel: path(versions.yml)
}
