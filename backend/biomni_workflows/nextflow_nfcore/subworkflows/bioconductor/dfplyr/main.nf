#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DFplyr
// Provides `dplyr` verbs (`mutate`, `select`, `filter`, etc...) supporting `S4Vectors::DataFrame` obje
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DFplyr/inst/doc/example_usage.R
// Upstream  : S4Vectors
// Downstream: none
//
// Install: BiocManager::install("DFplyr")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DFPLYR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-dfplyr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-dfplyr:1.0.0--r44_0' :
        'quay.io/biocontainers/bioconductor-dfplyr:1.0.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_dfplyr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_dfplyr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_dfplyr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DFplyr)
    library(jsonlite)

    # --- Column Selection and Renaming [] ---
    # Key functions: select, rename2, select_at
    d_selected <- DFplyr::select(d, am, cyl)
    d_renamed <- DFplyr::rename2(d_selected, foo = am)
    d_selected_at <- DFplyr::select_at(d, DFplyr::vars(starts_with("gr")))


    # --- Grouping and Summarisation [] ---
    # Key functions: group_by, tally, count
    d_grouped <- DFplyr::group_by(d, cyl, am)
    d_tally <- DFplyr::tally(d_grouped, gear)
    d_count <- DFplyr::count(d, gear, am, cyl)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_dfplyr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_dfplyr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_dfplyr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DFPLYR:", paste0("    dfplyr: ", packageVersion("DFplyr"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dfplyr_results.csv
    touch ${prefix}_dfplyr_output.rds
    echo "BIOC_DFPLYR:" > versions.yml
    echo "    dfplyr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DFPLYR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DFPLYR(ch_input)

    emit:
    results  = BIOC_DFPLYR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DFPLYR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DFPLYR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DFPLYR.out.versions  // channel: path(versions.yml)
}
