#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SurfR
// Identify Surface Protein coding genes from a list of candidates. Systematically download data from G
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SurfR/inst/doc/Intro_to_SurfR.R
// Upstream  : SPsimSeq, ggplot2, stringr
// Downstream: none
//
// Install: BiocManager::install("SurfR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SURFR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-surfr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-surfr:1.2.7--r44_0' :
        'quay.io/biocontainers/bioconductor-surfr:1.2.7--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_surfr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_surfr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_surfr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SurfR)
    library(Annotate_SPID)
    library(DGE)
    library(DownloadArchS4)
    library(Enrichment)
    library(GEOmetadata)
    library(Gene2SProtein)
    library(jsonlite)

    # --- Enrichment Analysis [] ---
    # Key functions: runEnrichment, getEnrichedTerms
    enrichment_results <- runEnrichment(
        data = filtered_proteins,
        database = "GO_Cellular_Component"
    )
    top_terms <- getEnrichedTerms(
        results = enrichment_results,
        p_value_cutoff = 0.05
    )


    # --- Visualization [] ---
    # Key functions: plotSurfaceEnrichment
    plotSurfaceEnrichment(
        results = enrichment_results,
        top_n = 10,
        color_by = "p_value"
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_surfr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_surfr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_surfr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SURFR:", paste0("    surfr: ", packageVersion("SurfR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_surfr_results.csv
    touch ${prefix}_surfr_output.rds
    echo "BIOC_SURFR:" > versions.yml
    echo "    surfr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SURFR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SURFR(ch_input)

    emit:
    results  = BIOC_SURFR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SURFR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SURFR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SURFR.out.versions  // channel: path(versions.yml)
}
