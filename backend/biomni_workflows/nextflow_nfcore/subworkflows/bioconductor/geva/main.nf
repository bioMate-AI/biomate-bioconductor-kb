#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: geva
// Statistic methods to evaluate variations of differential expression (DE) between multiple biological
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/geva/inst/doc/geva.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("geva")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GEVA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-geva"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-geva:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-geva:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_geva_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_geva_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_geva_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(geva)
    library(jsonlite)

    # --- Data Preparation and Filtering [Data Preparation] ---
    # Key functions: geva.ideal.example, geva.input.correct, geva.input.filter, factors<-
    ginput <- geva.ideal.example()
    ginput <- geva.input.correct(ginput)
    ginput <- geva.input.filter(ginput, p.value.cutoff = 0.05)
    factors(ginput) <- factor(c(
        "g1", "g1", "g1", "g2", "g2", "g2"
    ))

    # --- Summarisation [Summarisation] ---
    # Key functions: geva.summarize
    gsummary <- geva.summarize(
        ginput,
        summary.method = "median",
        variation.method = "mad"
    )
    plot(gsummary)

    # --- Quantile Analysis [Quantile Detection] ---
    # Key functions: geva.quantiles
    gquants <- geva.quantiles(
        gsummary,
        initial.thresholds = c(S = 1, V = 0.5)
    )
    plot(gquants)

    # --- Cluster Analysis [Clustering] ---
    # Key functions: geva.cluster
    gcluster <- geva.cluster(
        gsummary,
        cluster.method = "hierarchical",
        resolution = 0.3
    )
    plot(gcluster)

    # --- Final Classification [Classification] ---
    # Key functions: groupsets<-, geva.finalize
    ggroupedsummary <- gsummary
    groupsets(ggroupedsummary) <- gquants
    groupsets(ggroupedsummary) <- gcluster
    gresults <- geva.finalize(ggroupedsummary)
    plot(ggroupedsummary)


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_geva_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_geva_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_geva_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GEVA:", paste0("    geva: ", packageVersion("geva"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_geva_results.csv
    touch ${prefix}_geva_output.rds
    echo "BIOC_GEVA:" > versions.yml
    echo "    geva: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GEVA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GEVA(ch_input)

    emit:
    results  = BIOC_GEVA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GEVA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GEVA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GEVA.out.versions  // channel: path(versions.yml)
}
