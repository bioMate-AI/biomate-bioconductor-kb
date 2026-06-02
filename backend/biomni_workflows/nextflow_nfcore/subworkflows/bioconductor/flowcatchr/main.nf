#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: flowcatchR
// flowcatchR is a set of tools to analyze in vivo microscopy imaging data, focused on tracking flowing
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/flowcatchR/inst/doc/flowcatchr_vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("flowcatchR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FLOWCATCHR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-flowcatchr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-flowcatchr:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-flowcatchr:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_flowcatchr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_flowcatchr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_flowcatchr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(flowcatchR)
    library(jsonlite)

    # --- Maintainer analysis [] ---
    # Key functions: install_github, maintainer, kinematics, normalizeFrames, particles, penaltyFunctionGenerator, trajectories, snap
    allVelocities <- kinematics(trajPlatelets, feature="curvilinearVelocity")
    hist(allVelocities, breaks=10, probability=TRUE, col="cadetblue",
    lines(density(allVelocities, na.rm=TRUE), col="steelblue", lwd=2)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_flowcatchr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_flowcatchr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_flowcatchr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FLOWCATCHR:", paste0("    flowcatchr: ", packageVersion("flowcatchR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_flowcatchr_results.csv
    touch ${prefix}_flowcatchr_output.rds
    echo "BIOC_FLOWCATCHR:" > versions.yml
    echo "    flowcatchr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FLOWCATCHR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FLOWCATCHR(ch_input)

    emit:
    results  = BIOC_FLOWCATCHR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FLOWCATCHR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FLOWCATCHR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FLOWCATCHR.out.versions  // channel: path(versions.yml)
}
