#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: iPath
// iPath is the Bioconductor package used for calculating personalized pathway score and test the assoc
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/iPath/inst/doc/iPath.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("iPath")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_IPATH {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ipath"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ipath:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ipath:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ipath_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ipath_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ipath_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(iPath)
    library(jsonlite)

    # --- water_fall [] ---
    # Key functions: water_fall, density_fall
    water_fall(iES_mat, gs_str = "SimPathway2", indVec = prad_inds)
    density_fall(iES_mat, gs_str = "SimPathway2", indVec = prad_inds)
    # --- i E S_surv Plot [] ---
    # Key functions: iES_survPlot
    iES_survPlot(iES_mat = iES_mat, cli = prad_cli, gs_str = "SimPathway1", indVec = prad_inds, title = TRUE)
    sessionInfo()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ipath_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ipath_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ipath_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_IPATH:", paste0("    ipath: ", packageVersion("iPath"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ipath_results.csv
    touch ${prefix}_ipath_output.rds
    echo "BIOC_IPATH:" > versions.yml
    echo "    ipath: 0.0.0" >> versions.yml
    """
}


workflow BIOC_IPATH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_IPATH(ch_input)

    emit:
    results  = BIOC_IPATH.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_IPATH.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_IPATH.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_IPATH.out.versions  // channel: path(versions.yml)
}
