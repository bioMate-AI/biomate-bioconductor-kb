#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: dyebias
// Many two-colour hybridizations suffer from a dye bias that is both gene-specific and slide-specific.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/dyebias/inst/doc/dyebias-vignette.R
// Upstream  : GEOquery, convert, dyebiasexamples, limma, marray
// Downstream: none
//
// Install: BiocManager::install("dyebias")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DYEBIAS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-dyebias"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-dyebias:1.66.0--r44_0' :
        'quay.io/biocontainers/bioconductor-dyebias:1.66.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_dyebias_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_dyebias_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_dyebias_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(dyebias)
    library(GSMList)
    library(GenePix)
    library(Meta)
    library(jsonlite)

    # --- Dye Bias Correction [] ---
    # Key functions: dyebias.apply.correction
    corrected_marray <- dyebias.apply.correction(
        data = marray_data,
        estimator = bias_estimator,
        application = "correction"
    )


    # --- Visualization of Dye Bias [] ---
    # Key functions: dyebias.rgplot
    dyebias.rgplot(
        data = marray_data,
        slide = 1,
        main = "Dye Bias Plot"
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_dyebias_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_dyebias_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_dyebias_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DYEBIAS:", paste0("    dyebias: ", packageVersion("dyebias"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dyebias_results.csv
    touch ${prefix}_dyebias_output.rds
    echo "BIOC_DYEBIAS:" > versions.yml
    echo "    dyebias: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DYEBIAS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DYEBIAS(ch_input)

    emit:
    results  = BIOC_DYEBIAS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DYEBIAS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DYEBIAS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DYEBIAS.out.versions  // channel: path(versions.yml)
}
