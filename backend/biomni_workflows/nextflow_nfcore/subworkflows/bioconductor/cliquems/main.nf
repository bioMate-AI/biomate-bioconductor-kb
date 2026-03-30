#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: cliqueMS
// Annotates data from liquid chromatography coupled to mass spectrometry (LC/MS) metabolomics experime
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/cliqueMS/inst/doc/annotate_features.R
// Upstream  : xcms
// Downstream: none
//
// Install: BiocManager::install("cliqueMS")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CLIQUEMS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cliquems"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cliquems:1.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cliquems:1.20.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cliquems_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cliquems_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cliquems_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(cliqueMS)
    library(jsonlite)

    # --- show [] ---
    # Key functions: show
    ex.anClique <- createanClique(mzData)
    show(ex.anClique)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cliquems_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cliquems_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cliquems_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CLIQUEMS:", paste0("    cliquems: ", packageVersion("cliqueMS"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cliquems_results.csv
    touch ${prefix}_cliquems_output.rds
    echo "BIOC_CLIQUEMS:" > versions.yml
    echo "    cliquems: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CLIQUEMS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CLIQUEMS(ch_input)

    emit:
    results  = BIOC_CLIQUEMS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CLIQUEMS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CLIQUEMS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CLIQUEMS.out.versions  // channel: path(versions.yml)
}
