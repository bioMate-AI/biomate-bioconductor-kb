#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: chipenrich
// ChIP-Enrich and Poly-Enrich perform gene set enrichment testing using peaks called from a ChIP-seq e
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/chipenrich/inst/doc/chipenrich-vignette.R
// Upstream  : EGSEAdata
// Downstream: none
//
// Install: BiocManager::install("chipenrich")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CHIPENRICH {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-chipenrich"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-chipenrich:2.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-chipenrich:2.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_chipenrich_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_chipenrich_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_chipenrich_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(chipenrich)
    library(jsonlite)

    # --- Supported Genomes [] ---
    # Key functions: supported_genomes
    ---------------------------------------------------------------------
    supported_genomes()
    # --- Head [] ---
    # Key functions: supported_locusdefs
    ---------------------------------------------------------------------
    # Take head because it's long
    head(supported_locusdefs())
    # --- Head [] ---
    # Key functions: supported_genesets
    ---------------------------------------------------------------------
    # Take head because it's long
    head(supported_genesets())
    # --- Head [] ---
    # Key functions: supported_read_lengths
    ---------------------------------------------------------------------
    # Take head because it's long
    head(supported_read_lengths())

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_chipenrich_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_chipenrich_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_chipenrich_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CHIPENRICH:", paste0("    chipenrich: ", packageVersion("chipenrich"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chipenrich_results.csv
    touch ${prefix}_chipenrich_output.rds
    echo "BIOC_CHIPENRICH:" > versions.yml
    echo "    chipenrich: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CHIPENRICH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CHIPENRICH(ch_input)

    emit:
    results  = BIOC_CHIPENRICH.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CHIPENRICH.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CHIPENRICH.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CHIPENRICH.out.versions  // channel: path(versions.yml)
}
