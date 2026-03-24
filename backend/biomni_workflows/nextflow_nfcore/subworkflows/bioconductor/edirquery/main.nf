#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: EDIRquery
// EDIRquery provides a tool to search for genes of interest within the Exome Database of Interspersed 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/EDIRquery/inst/doc/EDIRquery.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("EDIRquery")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EDIRQUERY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-edirquery"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-edirquery:1.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-edirquery:1.6.0--r44_0'}"

    input:
    tuple val(meta), path(deseqdataset)

    output:
    tuple val(meta), path("${meta.id}_edirquery_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_edirquery_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_edirquery_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(EDIRquery)
    library(jsonlite)

    # --- Query results and gene lookup [] ---
    # Key functions: results, gene_lookup
    ---------------------------------------------------------------------
    # Summary of results (printed to console)
    gene_lookup("GAA", length = 7, mismatch = TRUE)
    # --- Gene Lookup [] ---
    # Key functions: gene_lookup
    ---------------------------------------------------------------------
    # Database output of query
    results <- gene_lookup("GAA", length = 7, mismatch = TRUE)
    head(results)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_edirquery_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_edirquery_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_edirquery_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_EDIRQUERY:", paste0("    edirquery: ", packageVersion("EDIRquery"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_edirquery_results.csv
    touch ${prefix}_edirquery_output.rds
    echo "BIOC_EDIRQUERY:" > versions.yml
    echo "    edirquery: 0.0.0" >> versions.yml
    """
}


workflow BIOC_EDIRQUERY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(deseqdataset) ]

    main:
    BIOC_EDIRQUERY(ch_input)

    emit:
    results  = BIOC_EDIRQUERY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_EDIRQUERY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_EDIRQUERY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_EDIRQUERY.out.versions  // channel: path(versions.yml)
}
