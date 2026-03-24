#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: pdInfoBuilder
// Builds platform design information packages. These consist of a SQLite database containing feature-l
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/pdInfoBuilder/inst/doc/howto-AffymetrixMapping.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("pdInfoBuilder")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PDINFOBUILDER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-pdinfobuilder"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-pdinfobuilder:1.70.0--r44_0' :
        'quay.io/biocontainers/bioconductor-pdinfobuilder:1.70.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_pdinfobuilder_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_pdinfobuilder_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_pdinfobuilder_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(pdInfoBuilder)
    library(jsonlite)

    # --- Build1 [] ---
    # Key functions: new, makePdInfoPackage
    ## library("pdInfoBuilder")
    ## cdfFile <- "Mapping250K_Nsp.cdf"
    ## csvAnno <- "Mapping250K_Nsp_annot.csv"
    ## csvSeq <- "Mapping250K_Nsp_probe_tab"
    ##

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_pdinfobuilder_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_pdinfobuilder_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_pdinfobuilder_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PDINFOBUILDER:", paste0("    pdinfobuilder: ", packageVersion("pdInfoBuilder"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pdinfobuilder_results.csv
    touch ${prefix}_pdinfobuilder_output.rds
    echo "BIOC_PDINFOBUILDER:" > versions.yml
    echo "    pdinfobuilder: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PDINFOBUILDER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PDINFOBUILDER(ch_input)

    emit:
    results  = BIOC_PDINFOBUILDER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PDINFOBUILDER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PDINFOBUILDER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PDINFOBUILDER.out.versions  // channel: path(versions.yml)
}
