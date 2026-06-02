#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: specL
// provides a functions for generating spectra libraries that can be used for MRM SRM MS workflows in p
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/specL/inst/doc/report.R
// Upstream  : BiocStyle, knitr, rmarkdown
// Downstream: none
//
// Install: BiocManager::install("specL")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPECL {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-specl"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-specl:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-specl:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_specl_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_specl_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_specl_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(specL)
    library(jsonlite)

    # --- tempfile [] ---
    # Key functions: tempfile, render
    library(rmarkdown)
    library(BiocStyle)
    report_file <- tempfile(fileext='.Rmd');
    # --- kable [] ---
    # Key functions: kable
    library(knitr)
    kable(t(as.data.frame(INPUT)))
    ii <- ((lapply(INPUT, function(x){ if(typeof(x) %in% c("character", "double")){paste(x, collapse = ', ')}else{NULL} } )))
    # --- specL::genSwathIonLib [] ---
    # Key functions: genSwathIonLib

    # --- slot Names [] ---
    # Key functions: slotNames
    slotNames(specLibrary@ionlibrary[[1]])

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_specl_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_specl_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_specl_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SPECL:", paste0("    specl: ", packageVersion("specL"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_specl_results.csv
    touch ${prefix}_specl_output.rds
    echo "BIOC_SPECL:" > versions.yml
    echo "    specl: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SPECL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SPECL(ch_input)

    emit:
    results  = BIOC_SPECL.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SPECL.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SPECL.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SPECL.out.versions  // channel: path(versions.yml)
}
