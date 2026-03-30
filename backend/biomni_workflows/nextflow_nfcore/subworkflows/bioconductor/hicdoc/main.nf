#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: HiCDOC
// HiCDOC normalizes intrachromosomal Hi-C matrices, uses unsupervised learning to predict A/B compartm
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/HiCDOC/inst/doc/HiCDOC.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("HiCDOC")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HICDOC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-hicdoc"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-hicdoc:1.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-hicdoc:1.8.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_hicdoc_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_hicdoc_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_hicdoc_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(HiCDOC)
    library(jsonlite)

    # --- normalize Distance Effect [] ---
    # Key functions: normalizeDistanceEffect
    normalizeDistanceEffect(hic.experiment, loessSampleSize = 20000)
    # --- plot Interactions [] ---
    # Key functions: plotInteractions
    p <- plotInteractions(hic.experiment, chromosome = "Y")
    # --- plot Distance Effect [] ---
    # Key functions: plotDistanceEffect
    p <- plotDistanceEffect(hic.experiment)
    # --- compartments [] ---
    # Key functions: compartments
    compartments(hic.experiment)
    # --- concordances [] ---
    # Key functions: concordances
    concordances(hic.experiment)
    # --- differences [] ---
    # Key functions: differences
    differences(hic.experiment)
    # --- plot Compartment Changes [] ---
    # Key functions: plotCompartmentChanges
    p <- plotCompartmentChanges(hic.experiment, chromosome = "Y")
    # --- plot Concordance Differences [] ---
    # Key functions: plotConcordanceDifferences
    p <- plotConcordanceDifferences(hic.experiment)
    # --- plot Centroids [] ---
    # Key functions: plotCentroids
    p <- plotCentroids(hic.experiment, chromosome = "Y")
    # --- plot Self Interaction Ratios [] ---
    # Key functions: plotSelfInteractionRatios
    p <- plotSelfInteractionRatios(hic.experiment, chromosome = "Y")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_hicdoc_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_hicdoc_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_hicdoc_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_HICDOC:", paste0("    hicdoc: ", packageVersion("HiCDOC"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hicdoc_results.csv
    touch ${prefix}_hicdoc_output.rds
    echo "BIOC_HICDOC:" > versions.yml
    echo "    hicdoc: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HICDOC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_HICDOC(ch_input)

    emit:
    results  = BIOC_HICDOC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HICDOC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HICDOC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HICDOC.out.versions  // channel: path(versions.yml)
}
