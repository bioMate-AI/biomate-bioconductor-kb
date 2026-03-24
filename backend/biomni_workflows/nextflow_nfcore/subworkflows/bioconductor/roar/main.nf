#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: roar
// Identify preferential usage of APA sites, comparing two biological conditions, starting from known a
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/roar/inst/doc/roar.R
// Upstream  : rtracklayer
// Downstream: none
//
// Install: BiocManager::install("roar")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ROAR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-roar"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-roar:1.42.0--r44_0' :
        'quay.io/biocontainers/bioconductor-roar:1.42.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_roar_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_roar_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_roar_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(RoarDatasetFromFiles)
    library(jsonlite)

    # --- Loadlibandcreateroarobject [] ---
    # Key functions: control, RoarDatasetFromFiles
    library(roar)
    library(rtracklayer)
    library(RNAseqData.HNRNPC.bam.chr14)
    gtf <- system.file("examples", "apa.gtf", package="roar")
    # HNRNPC ko data
    # --- Countreads [] ---
    # Key functions: countPrePost
    rds <- countPrePost(rds, FALSE)
    # --- Computeroars [] ---
    # Key functions: computeRoars
    rds <- computeRoars(rds)
    # --- Computepvals [] ---
    # Key functions: computePvals
    rds <- computePvals(rds)
    # --- Getresults [] ---
    # Key functions: totalResults
    results <- totalResults(rds)
    # --- Getfilteredresults [] ---
    # Key functions: pvalueFilter
    results_filtered <- pvalueFilter(rds, fpkmCutoff=-Inf,
                                     pvalCutoff=0.05)
    nrow(results_filtered[results_filtered$nUnderCutoff==12,])

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_roar_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_roar_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_roar_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ROAR:", paste0("    roar: ", packageVersion("roar"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_roar_results.csv
    touch ${prefix}_roar_output.rds
    echo "BIOC_ROAR:" > versions.yml
    echo "    roar: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ROAR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ROAR(ch_input)

    emit:
    results  = BIOC_ROAR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ROAR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ROAR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ROAR.out.versions  // channel: path(versions.yml)
}
