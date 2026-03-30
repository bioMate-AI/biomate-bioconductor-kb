#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: kmcut
// The purpose of the package is to identify prognostic biomarkers and an optimal numeric cutoff for ea
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/kmcut/inst/doc/kmcut_intro.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("kmcut")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_KMCUT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-kmcut"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-kmcut:1.0.0--r44_0' :
        'quay.io/biocontainers/bioconductor-kmcut:1.0.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_kmcut_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_kmcut_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_kmcut_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(kmcut)
    library(jsonlite)

    # --- Training [] ---
    # Key functions: training, test, create_se_object, ucox_pred
    ---------------------------------------------------------------------
    # Read names of the built-in training (fdat1) and test (fdat2)
    # gene expression data files and survival data file (sdat)
    fdat1 = system.file("extdata", "expression_data_1.txt", package = "kmcut")
    fdat2 = system.file("extdata", "expression_data_2.txt", package = "kmcut")
    # --- Genes [] ---
    # Key functions: genes, id, extract_rows
    ---------------------------------------------------------------------
    # Read the name of the built-in gene expression data file with 2 genes (2 rows)
    fdat = system.file("extdata", "example_genes.txt", package = "kmcut")
    # Read the name of the built-in list file that contains one gene id (MYCN)
    idlist = system.file("extdata", "rowids.txt", package = "kmcut")
    # --- Genes [] ---
    # Key functions: genes, column, extract_columns
    ---------------------------------------------------------------------
    # Read the name of the built-in gene expression data file with 2 genes (2 rows)
    fdat = system.file("extdata", "example_genes.txt", package = "kmcut")
    # Read the name of the built-in list file that contains a sub-set of
    # column (sample) ids

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_kmcut_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_kmcut_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_kmcut_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_KMCUT:", paste0("    kmcut: ", packageVersion("kmcut"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_kmcut_results.csv
    touch ${prefix}_kmcut_output.rds
    echo "BIOC_KMCUT:" > versions.yml
    echo "    kmcut: 0.0.0" >> versions.yml
    """
}


workflow BIOC_KMCUT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_KMCUT(ch_input)

    emit:
    results  = BIOC_KMCUT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_KMCUT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_KMCUT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_KMCUT.out.versions  // channel: path(versions.yml)
}
