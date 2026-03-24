#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: semisup
// Implements a parametric semi-supervised mixture model. The permutation test detects markers with mai
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/semisup/inst/doc/semisup.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("semisup")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SEMISUP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-semisup"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-semisup:1.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-semisup:1.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_semisup_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_semisup_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_semisup_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(semisup)
    library(jsonlite)

    # --- Mixtura [] ---
    # Key functions: mixtura
    -------------------------------------------------
    fit <- mixtura(y,z)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_semisup_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_semisup_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_semisup_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SEMISUP:", paste0("    semisup: ", packageVersion("semisup"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_semisup_results.csv
    touch ${prefix}_semisup_output.rds
    echo "BIOC_SEMISUP:" > versions.yml
    echo "    semisup: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SEMISUP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SEMISUP(ch_input)

    emit:
    results  = BIOC_SEMISUP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SEMISUP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SEMISUP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SEMISUP.out.versions  // channel: path(versions.yml)
}
