#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: tenXplore
// Perform ontological exploration of scRNA-seq of 1.3 million mouse neurons from 10x genomics.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/tenXplore/inst/doc/tenXplore.R
// Upstream  : ontoProc
// Downstream: none
//
// Install: BiocManager::install("tenXplore")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TENXPLORE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-tenxplore"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-tenxplore:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-tenxplore:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_tenxplore_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_tenxplore_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_tenxplore_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(tenXplore)
    library(jsonlite)


    # --- Setupp [] ---
    # Key functions: suppressWarnings, suppressPackageStartupMessages
    suppressWarnings({
    suppressPackageStartupMessages({
    library(tenXplore)
    library(org.Mm.eg.db)
    library(org.Hs.eg.db)
    })
    })

    # --- Doont [] ---
    # Key functions: cellTypeToGO, cellTypeToGenes
    library(ontoProc)
    data(allGOterms)
    cellTypeToGO("serotonergic neuron", gotab=allGOterms)
    cellTypeToGenes("serotonergic neuron", gotab=allGOterms, orgDb=org.Mm.eg.db)
    cellTypeToGenes("serotonergic neuron", gotab=allGOterms, orgDb=org.Hs.eg.db)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_tenxplore_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_tenxplore_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_tenxplore_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TENXPLORE:", paste0("    tenxplore: ", packageVersion("tenXplore"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tenxplore_results.csv
    touch ${prefix}_tenxplore_output.rds
    echo "BIOC_TENXPLORE:" > versions.yml
    echo "    tenxplore: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TENXPLORE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TENXPLORE(ch_input)

    emit:
    results  = BIOC_TENXPLORE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TENXPLORE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TENXPLORE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TENXPLORE.out.versions  // channel: path(versions.yml)
}
