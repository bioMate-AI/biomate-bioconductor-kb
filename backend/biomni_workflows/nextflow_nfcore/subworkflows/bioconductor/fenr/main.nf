#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: fenr
// Perform fast functional enrichment on feature lists (like genes or proteins) using the hypergeometri
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/fenr/inst/doc/fenr.R
// Upstream  : tibble, topGO
// Downstream: none
//
// Install: BiocManager::install("fenr")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FENR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-fenr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-fenr:1.4.2--r44_0' :
        'quay.io/biocontainers/bioconductor-fenr:1.4.2--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_fenr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_fenr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_fenr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(fenr)
    library(jsonlite)

    # --- Fetch go analysis [] ---
    # Key functions: include_graphics, fetch_go, fetch_go_species, prepare_for_enrichment, functional_enrichment, fetch_terms_for_example, enrichment_interactive, setNames
    go <- fetch_go(species = "sgd")
    go_terms <- prepare_for_enrichment(go$terms, go$mapping, exmpl_all,
    enr <- functional_enrichment(exmpl_all, exmpl_sel, go_terms)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_fenr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_fenr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_fenr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FENR:", paste0("    fenr: ", packageVersion("fenr"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fenr_results.csv
    touch ${prefix}_fenr_output.rds
    echo "BIOC_FENR:" > versions.yml
    echo "    fenr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FENR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FENR(ch_input)

    emit:
    results  = BIOC_FENR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FENR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FENR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FENR.out.versions  // channel: path(versions.yml)
}
