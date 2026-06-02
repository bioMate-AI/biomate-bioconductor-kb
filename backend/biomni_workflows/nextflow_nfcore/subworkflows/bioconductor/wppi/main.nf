#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: wppi
// Protein-protein interaction data is essential for omics data analysis and modeling. Database knowled
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/wppi/inst/doc/wppi_workflow.R
// Upstream  : knitr
// Downstream: none
//
// Install: BiocManager::install("wppi")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_WPPI {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-wppi"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-wppi:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-wppi:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_wppi_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_wppi_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_wppi_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(wppi)
    library(jsonlite)


    # --- Workflow [] ---
    # Key functions: score_candidate_genes_from_PPI
    library(wppi)
    # example gene set
    genes_interest <- c(
        'ERCC8', 'AKT3', 'NOL3', 'TTK',
        'GFI1B', 'CDC25A', 'TPX2', 'SHE'
    )
    scores <- score_candidate_genes_from_PPI(genes_interest)
    scores
    # # A tibble: 295 x 3
    #    score gene_symbol uniprot
    #    <dbl> <chr>       <chr>
    #  1 0.247 KNL1        Q8NG31
    #  2 0.247 HTRA2       O43464
    #  3 0.247 KAT6A       Q92794
    #  4 0.247 BABAM1      Q9NWV8

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_wppi_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_wppi_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_wppi_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_WPPI:", paste0("    wppi: ", packageVersion("wppi"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_wppi_results.csv
    touch ${prefix}_wppi_output.rds
    echo "BIOC_WPPI:" > versions.yml
    echo "    wppi: 0.0.0" >> versions.yml
    """
}


workflow BIOC_WPPI_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_WPPI(ch_input)

    emit:
    results  = BIOC_WPPI.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_WPPI.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_WPPI.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_WPPI.out.versions  // channel: path(versions.yml)
}
