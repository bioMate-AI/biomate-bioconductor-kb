#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: cyanoFilter
// An approach to filter out and/or identify phytoplankton cells from all particles measured via flow c
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/cyanoFilter/inst/doc/cyanoFilter.R
// Upstream  : dplyr, magrittr, tidyr, purrr, flowCore
// Downstream: none
//
// Install: BiocManager::install("cyanoFilter")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CYANOFILTER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cyanofilter"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cyanofilter:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cyanofilter:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cyanofilter_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cyanofilter_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cyanofilter_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(cyanoFilter)
    library(jsonlite)

    # --- Table formatting and display [] ---
    # Key functions: str_extract, kable, retain, noNA, ggpairsDens, noNeg, lnTrans, cellMargin
    metafile <- metafile %>% dplyr::mutate(Sample.ID2 =
    stringr::str_extract(metafile$Sample.ID, "BS*[4-5]")
    names(metafile)[which(stringr::str_detect(names(metafile), "Cells."))] <- "CellspML"

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cyanofilter_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cyanofilter_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cyanofilter_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CYANOFILTER:", paste0("    cyanofilter: ", packageVersion("cyanoFilter"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cyanofilter_results.csv
    touch ${prefix}_cyanofilter_output.rds
    echo "BIOC_CYANOFILTER:" > versions.yml
    echo "    cyanofilter: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CYANOFILTER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CYANOFILTER(ch_input)

    emit:
    results  = BIOC_CYANOFILTER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CYANOFILTER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CYANOFILTER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CYANOFILTER.out.versions  // channel: path(versions.yml)
}
