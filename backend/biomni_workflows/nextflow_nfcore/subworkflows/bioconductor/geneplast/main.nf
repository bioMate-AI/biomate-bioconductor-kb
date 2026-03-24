#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: geneplast
// Geneplast is designed for evolutionary and plasticity analysis based on orthologous groups distribut
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/geneplast/inst/doc/geneplast.R
// Upstream  : Fletcher2013b, RColorBrewer, RTN, RedeR, egg
// Downstream: none
//
// Install: BiocManager::install("geneplast")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENEPLAST {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-geneplast"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-geneplast:1.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-geneplast:1.32.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_geneplast_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_geneplast_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_geneplast_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(geneplast)
    library(jsonlite)

    # --- label='gplastTest' [] ---
    # Key functions: gplast
    ogp <- gplast(ogp, verbose=FALSE)
    # --- label='grootTest' [] ---
    # Key functions: groot
    set.seed(1)
    ogr <- groot(ogr, nPermutations=100, verbose=FALSE)
    # --- label='runtime' [] ---
    # Key functions: groot
    library(ggplot2)
    library(ggthemes)
    library(egg)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_geneplast_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_geneplast_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_geneplast_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GENEPLAST:", paste0("    geneplast: ", packageVersion("geneplast"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_geneplast_results.csv
    touch ${prefix}_geneplast_output.rds
    echo "BIOC_GENEPLAST:" > versions.yml
    echo "    geneplast: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GENEPLAST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GENEPLAST(ch_input)

    emit:
    results  = BIOC_GENEPLAST.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GENEPLAST.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GENEPLAST.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GENEPLAST.out.versions  // channel: path(versions.yml)
}
