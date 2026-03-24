#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: profileScoreDist
// Regularization and score distributions for position count matrices.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/profileScoreDist/inst/doc/profileScoreDist-vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("profileScoreDist")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PROFILESCOREDIST {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-profilescoredist"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-profilescoredist:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-profilescoredist:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_profilescoredist_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_profilescoredist_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_profilescoredist_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(profileScoreDist)
    library(jsonlite)

    # --- plot Dist [] ---
    # Key functions: plotDist
    plotDist(distlist[[50]])
    # --- score Dist Cutoffs [] ---
    # Key functions: scoreDistCutoffs
    ab5 <- scoreDistCutoffs(distlist[[50]], 500, 1, c=1, 0.05)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_profilescoredist_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_profilescoredist_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_profilescoredist_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PROFILESCOREDIST:", paste0("    profilescoredist: ", packageVersion("profileScoreDist"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_profilescoredist_results.csv
    touch ${prefix}_profilescoredist_output.rds
    echo "BIOC_PROFILESCOREDIST:" > versions.yml
    echo "    profilescoredist: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PROFILESCOREDIST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PROFILESCOREDIST(ch_input)

    emit:
    results  = BIOC_PROFILESCOREDIST.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PROFILESCOREDIST.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PROFILESCOREDIST.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PROFILESCOREDIST.out.versions  // channel: path(versions.yml)
}
