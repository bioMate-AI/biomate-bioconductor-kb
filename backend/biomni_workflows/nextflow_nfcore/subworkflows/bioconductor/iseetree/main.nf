#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: iSEEtree
// iSEEtree is an extension of iSEE for the TreeSummarizedExperiment. It leverages the functionality fr
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/iSEEtree/inst/doc/iSEEtree.R
// Upstream  : RefManageR, mia, scater
// Downstream: none
//
// Install: BiocManager::install("iSEEtree")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ISEETREE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-iseetree"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-iseetree:1.0.0--r44_0' :
        'quay.io/biocontainers/bioconductor-iseetree:1.0.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_iseetree_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_iseetree_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_iseetree_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(PrintBibliography)
    library(SCREENSHOT)
    library(jsonlite)

    # --- transform Assay [] ---
    # Key functions: transformAssay, runMDS, iSEE
    library(iSEEtree)
    library(mia)
    library(scater)
    # --- S C R E E N S H O T [] ---
    # Key functions: SCREENSHOT
    SCREENSHOT("screenshots/get_started.png", delay=20)
    # --- Print Bibliography [] ---
    # Key functions: PrintBibliography
    PrintBibliography(bib, .opts = list(hyperlink = "to.doc", style = "html"))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_iseetree_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_iseetree_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_iseetree_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ISEETREE:", paste0("    iseetree: ", packageVersion("iSEEtree"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_iseetree_results.csv
    touch ${prefix}_iseetree_output.rds
    echo "BIOC_ISEETREE:" > versions.yml
    echo "    iseetree: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ISEETREE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ISEETREE(ch_input)

    emit:
    results  = BIOC_ISEETREE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ISEETREE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ISEETREE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ISEETREE.out.versions  // channel: path(versions.yml)
}
