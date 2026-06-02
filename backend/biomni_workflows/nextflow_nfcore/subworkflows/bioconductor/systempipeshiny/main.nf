#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: systemPipeShiny
// systemPipeShiny (SPS) extends the widely used systemPipeR (SPR) workflow environment with a versatil
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/systemPipeShiny/inst/doc/systemPipeShiny.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("systemPipeShiny")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SYSTEMPIPESHINY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-systempipeshiny"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-systempipeshiny:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-systempipeshiny:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_systempipeshiny_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_systempipeshiny_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_systempipeshiny_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(systemPipeShiny)
    library(jsonlite)


    # --- Logo [] ---
    # Key functions: include_graphics
    knitr::include_graphics(path = "../inst/app/www/img/logo.png")

    # --- Spsinit Temp [] ---
    # Key functions: tempdir, spsInit
    sps_tmp_dir <- tempdir()
    spsInit(app_path = sps_tmp_dir, change_wd = FALSE, project_name = "SPSProject")
    sps_dir <- file.path(sps_tmp_dir, "SPSProject")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_systempipeshiny_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_systempipeshiny_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_systempipeshiny_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SYSTEMPIPESHINY:", paste0("    systempipeshiny: ", packageVersion("systemPipeShiny"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_systempipeshiny_results.csv
    touch ${prefix}_systempipeshiny_output.rds
    echo "BIOC_SYSTEMPIPESHINY:" > versions.yml
    echo "    systempipeshiny: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SYSTEMPIPESHINY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SYSTEMPIPESHINY(ch_input)

    emit:
    results  = BIOC_SYSTEMPIPESHINY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SYSTEMPIPESHINY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SYSTEMPIPESHINY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SYSTEMPIPESHINY.out.versions  // channel: path(versions.yml)
}
