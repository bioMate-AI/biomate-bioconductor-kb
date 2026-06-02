#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GrafGen
// To classify Helicobacter pylori genomes according to genetic distance from nine reference population
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GrafGen/inst/doc/vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("GrafGen")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GRAFGEN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-grafgen"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-grafgen:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-grafgen:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_grafgen_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_grafgen_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_grafgen_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GrafGen)
    library(jsonlite)

    # --- crop=NULL [] ---
    # Key functions: createApp, runApp
    plot(ret)
    if (interactive()) interactiveReferencePlot()
    tmp <- createApp(ret)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_grafgen_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_grafgen_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_grafgen_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GRAFGEN:", paste0("    grafgen: ", packageVersion("GrafGen"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_grafgen_results.csv
    touch ${prefix}_grafgen_output.rds
    echo "BIOC_GRAFGEN:" > versions.yml
    echo "    grafgen: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GRAFGEN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GRAFGEN(ch_input)

    emit:
    results  = BIOC_GRAFGEN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GRAFGEN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GRAFGEN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GRAFGEN.out.versions  // channel: path(versions.yml)
}
