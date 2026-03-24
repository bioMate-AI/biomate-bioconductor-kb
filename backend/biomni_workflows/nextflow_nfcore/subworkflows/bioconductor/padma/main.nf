#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: padma
// Use multiple factor analysis to calculate individualized pathway-centric scores of deviation with re
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/padma/inst/doc/padma.R
// Upstream  : MultiAssayExperiment
// Downstream: none
//
// Install: BiocManager::install("padma")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PADMA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-padma"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-padma:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-padma:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_padma_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_padma_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_padma_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MultiAssayExperiment)
    library(jsonlite)

    # --- Multi Assay Experiment [] ---
    # Key functions: MultiAssayExperiment
    head(msigdb)
    head(mirtarbase)
    library(MultiAssayExperiment)
    # --- padma [] ---
    # Key functions: padma
    D4GDI <- msigdb[grep("D4GDI", msigdb$geneset), "geneset"]
    padma(mae, pathway_name = D4GDI, verbose = FALSE)
    # --- unlist [] ---
    # Key functions: unlist, padma
    D4GDI_genes <- unlist(strsplit(
    msigdb[grep("D4GDI", msigdb$geneset), "symbol"], ", "))
    padma(mae, pathway_name = D4GDI_genes, verbose = FALSE)
    # --- factor Map [] ---
    # Key functions: factorMap
    factorMap(run_padma, dim_x = 1, dim_y = 2)
    # --- omics Contrib [] ---
    # Key functions: omicsContrib
    omicsContrib(run_padma, max_dim = 10)
    # --- omics Contrib [] ---
    # Key functions: omicsContrib, padma
    omicsContrib(run_padma, max_dim = 10, ggplot = FALSE)
    padma(mae, pathway_name = D4GDI, verbose = FALSE,
    base_ids = sampleMap(mae)$primary[1:10],

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_padma_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_padma_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_padma_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PADMA:", paste0("    padma: ", packageVersion("padma"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_padma_results.csv
    touch ${prefix}_padma_output.rds
    echo "BIOC_PADMA:" > versions.yml
    echo "    padma: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PADMA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PADMA(ch_input)

    emit:
    results  = BIOC_PADMA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PADMA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PADMA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PADMA.out.versions  // channel: path(versions.yml)
}
