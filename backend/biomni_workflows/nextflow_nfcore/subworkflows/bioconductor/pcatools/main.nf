#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: PCAtools
// Principal Component Analysis (PCA) is a very powerful technique that has wide applicability in data 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/PCAtools/inst/doc/PCAtools.R
// Upstream  : Biobase, DESeq2, GEOquery, airway, cowplot
// Downstream: OSCA.advanced
//
// Install: BiocManager::install("PCAtools")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PCATOOLS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-pcatools"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-pcatools:2.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-pcatools:2.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_pcatools_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_pcatools_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_pcatools_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(PCAtools)
    library(jsonlite)

    # --- Dimensionality Reduction Visualization [] ---
    # Key functions: screeplot, biplot, pairsplot
    screeplot(
        p,
        components = getComponents(p, 1:20),
        vline = c(horn$n, elbow)
    )
    biplot(
        p,
        showLoadings = TRUE,
        lab = NULL
    )
    pairsplot(p)


    # --- Loadings and Metadata Association [] ---
    # Key functions: plotloadings, eigencorplot
    plotloadings(
        p,
        labSize = 3
    )
    eigencorplot(
        p,
        metavars = c("Study", "Age", "ER", "Grade")
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_pcatools_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_pcatools_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_pcatools_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PCATOOLS:", paste0("    pcatools: ", packageVersion("PCAtools"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pcatools_results.csv
    touch ${prefix}_pcatools_output.rds
    echo "BIOC_PCATOOLS:" > versions.yml
    echo "    pcatools: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PCATOOLS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PCATOOLS(ch_input)

    emit:
    results  = BIOC_PCATOOLS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PCATOOLS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PCATOOLS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PCATOOLS.out.versions  // channel: path(versions.yml)
}
