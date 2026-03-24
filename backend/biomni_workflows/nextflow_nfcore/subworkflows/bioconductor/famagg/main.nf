#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: FamAgg
// Framework providing basic pedigree analysis and plotting utilities as well as a variety of methods t
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/FamAgg/inst/doc/FamAgg.R
// Upstream  : BiocStyle, gap
// Downstream: none
//
// Install: BiocManager::install("FamAgg")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FAMAGG {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-famagg"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-famagg:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-famagg:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_famagg_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_famagg_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_famagg_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(FAData)
    library(jsonlite)

    # --- FAData analysis [] ---
    # Key functions: FAData, switchPlotfun, plotPed, buildPed, any, findFounders, getCommonAncestor, getChildren
    Perform the analysis (no strata etc) separately for each family.
    giFam <- genealogicalIndexTest(fad, trait = tcancer, nsim = nsim,
    head(result(giFam))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_famagg_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_famagg_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_famagg_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FAMAGG:", paste0("    famagg: ", packageVersion("FamAgg"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_famagg_results.csv
    touch ${prefix}_famagg_output.rds
    echo "BIOC_FAMAGG:" > versions.yml
    echo "    famagg: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FAMAGG_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FAMAGG(ch_input)

    emit:
    results  = BIOC_FAMAGG.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FAMAGG.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FAMAGG.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FAMAGG.out.versions  // channel: path(versions.yml)
}
