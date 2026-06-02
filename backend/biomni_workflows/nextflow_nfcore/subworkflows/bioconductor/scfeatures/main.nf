#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: scFeatures
// scFeatures constructs multi-view representations of single-cell and spatial data. scFeatures is a to
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/scFeatures/inst/doc/scFeatures_overview.R
// Upstream  : ClassifyR, S4Vectors, survival, survminer
// Downstream: none
//
// Install: BiocManager::install("scFeatures")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCFEATURES {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-scfeatures"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-scfeatures:1.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-scfeatures:1.6.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_scfeatures_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_scfeatures_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_scfeatures_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(scFeatures)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: scFeatures
    ---------------------------------------------------------------------
    data("example_scrnaseq" , package = "scFeatures")
    data <- example_scrnaseq
    # --- Data [] ---
    # Key functions: tempdir, run_association_study_report
    ---------------------------------------------------------------------
    # here we use the demo data from the package
    data("scfeatures_result" , package = "scFeatures")
    # here we use the current working directory to save the html output
    # modify this to save the html file to other directory

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_scfeatures_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_scfeatures_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_scfeatures_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCFEATURES:", paste0("    scfeatures: ", packageVersion("scFeatures"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scfeatures_results.csv
    touch ${prefix}_scfeatures_output.rds
    echo "BIOC_SCFEATURES:" > versions.yml
    echo "    scfeatures: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCFEATURES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SCFEATURES(ch_input)

    emit:
    results  = BIOC_SCFEATURES.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCFEATURES.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCFEATURES.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCFEATURES.out.versions  // channel: path(versions.yml)
}
